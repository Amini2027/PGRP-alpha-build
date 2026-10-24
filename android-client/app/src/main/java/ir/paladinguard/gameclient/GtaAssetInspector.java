package ir.paladinguard.gameclient;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;

import java.io.IOException;
import java.io.InputStream;
import java.util.Collections;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Android 9+ scoped, user-selected folder inspection via Storage Access Framework.
 * Does not request storage-wide permission, doesn't copy GBs of data, doesn't
 * publish any Rockstar proprietary data, and cannot access Windows C:\ paths.
 */
public final class GtaAssetInspector {
    private static final String DIR=DocumentsContract.Document.MIME_TYPE_DIR;

    private final Context context;
    private final Uri tree;
    private final ContentResolver resolver;

    public static final class Report {
        public final boolean readyForIndexing;
        public final String details;
        public final int objects;
        public Report(boolean readyForIndexing,String details,int objects){
            this.readyForIndexing=readyForIndexing;
            this.details=details;
            this.objects=objects;
        }
    }
    private static final class FileRef {
        final String id;
        final String mime;
        final long size;
        FileRef(String id,String mime,long size){
            this.id=id;this.mime=mime;this.size=size;
        }
        boolean isFolder(){return DIR.equals(mime);}
    }

    public GtaAssetInspector(Context context,Uri tree){
        this.context=context.getApplicationContext();
        this.tree=tree;
        resolver=this.context.getContentResolver();
    }

    private Map<String,FileRef> children(String parentId) throws IOException {
        Uri uri=DocumentsContract.buildChildDocumentsUriUsingTree(tree,parentId);
        Map<String,FileRef> map=new HashMap<>();
        String[] columns={
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE
        };
        try(Cursor c=resolver.query(uri,columns,null,null,null)){
            if(c==null)throw new IOException("Storage provider returned no listing");
            int idIndex=c.getColumnIndexOrThrow(columns[0]);
            int nameIndex=c.getColumnIndexOrThrow(columns[1]);
            int mimeIndex=c.getColumnIndexOrThrow(columns[2]);
            int sizeIndex=c.getColumnIndexOrThrow(columns[3]);
            int count=0;
            while(c.moveToNext()){
                if(++count>10000)throw new IOException("Directory is too large");
                String id=c.getString(idIndex);
                String name=c.getString(nameIndex);
                String mime=c.getString(mimeIndex);
                long size=c.isNull(sizeIndex)?-1L:c.getLong(sizeIndex);
                if(id!=null && name!=null && mime!=null)
                    map.put(name.toLowerCase(Locale.ROOT),new FileRef(id,mime,size));
            }
            return map;
        }catch(SecurityException e){
            throw new IOException("Access to chosen directory was denied",e);
        }catch(RuntimeException e){
            throw new IOException("Unable to list selected folder",e);
        }
    }

    private InputStream open(FileRef file) throws IOException {
        Uri fileUri=DocumentsContract.buildDocumentUriUsingTree(tree,file.id);
        try {
            InputStream in=resolver.openInputStream(fileUri);
            if(in==null)throw new IOException("Unable to open selected GTA document");
            return in;
        }catch(SecurityException e){
            throw new IOException("Storage access was denied",e);
        }
    }

    public Report inspect() throws IOException {
        String rootId=DocumentsContract.getTreeDocumentId(tree);
        Map<String,FileRef> root=children(rootId);
        FileRef data=root.get("data");
        FileRef models=root.get("models");
        StringBuilder result=new StringBuilder();
        result.append("GTA San Andreas PC — بررسی فایل‌های محلی\n\n");
        if(data==null||!data.isFolder()||models==null||!models.isFolder()){
            result.append("پوشه انتخاب‌شده باید خود GTA.San.Andreas باشد و دو پوشه data و models داخل آن قرار داشته باشند.\n");
            result.append("data: ").append(data!=null && data.isFolder()?"موجود":"پیدا نشد").append("\n");
            result.append("models: ").append(models!=null && models.isFolder()?"موجود":"پیدا نشد");
            return new Report(false,result.toString(),0);
        }
        Map<String,FileRef> entries=children(models.id);
        Map<String,FileRef> dataEntries=children(data.id);
        boolean gtaDat=has(dataEntries,"gta.dat",false);
        boolean maps=has(dataEntries,"maps",true);
        result.append("data/gta.dat: ").append(gtaDat?"✓":"✗").append("\n");
        result.append("data/maps: ").append(maps?"✓":"✗").append("\n");
        boolean threeDArchive=has(entries,"gta3.img",false);
        boolean player=has(entries,"player.img",false);
        boolean interior=has(entries,"gta_int.img",false);
        result.append("models/gta3.img: ").append(threeDArchive?"✓":"✗").append("\n");
        result.append("models/player.img: ").append(player?"✓":"✗").append("\n");
        result.append("models/gta_int.img: ").append(interior?"✓":"✗").append("\n");

        if(!threeDArchive||!player||!interior||!gtaDat||!maps){
            result.append("\nبرخی اجزای اصلی موجود نیستند؛ فایل‌ها را از نسخه قانونی و کامل بازی انتخاب کن.");
            return new Report(false,result.toString(),0);
        }
        FileRef archive=entries.get("gta3.img");
        if(archive.size<0){
            result.append("\nارائه‌دهنده حافظه اندازه فایل IMG را اعلام نمی‌کند؛ بررسی فرمت امکان‌پذیر نیست.");
            return new Report(false,result.toString(),0);
        }
        result.append("\nحجم gta3.img: ").append(archive.size/(1024*1024)).append(" MiB");
        final GtaImgIndex.Result index;
        try(InputStream in=open(archive)){
            index=GtaImgIndex.parse(in,archive.size);
        }catch(IOException failure){
            result.append("\nخطا در ساختار آرشیو: ").append(failure.getMessage());
            return new Report(false,result.toString(),0);
        }
        result.append("\nفرمت IMG: VER2 ✓");
        result.append("\nتعداد ورودی‌های IMG: ").append(index.count);
        result.append("\nچند مدل شناسایی‌شده:");
        for(GtaImgIndex.Sample sample:index.samples)result.append("\n  • ").append(sample.name);
        result.append("\n\nساختار فایل‌های اولیه تأیید شد. این مرحله فقط شناسایی فایل و نمایه آرشیو است؛ نمایش نقشه واقعی، TXD/DFF/IDE/IPL و ورود به سرور هنوز پیاده نشده‌اند.");
        return new Report(true,result.toString(),index.count);
    }

    private static boolean has(Map<String,FileRef> map,String name,boolean folder){
        FileRef file=map.get(name);
        return file!=null && file.isFolder()==folder;
    }
}
