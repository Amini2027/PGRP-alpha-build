package ir.paladinguard.gameclient;

import android.content.Context;
import android.content.ContentResolver;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** SAF source for user-selected local GTA directory on Android 9+.
 * No storage-wide access, file writes, uploads or copying proprietary data.
 */
public final class GtaMapSafSource implements GtaMapPlacementIndex.Source {
    private static final String DIRECTORY=DocumentsContract.Document.MIME_TYPE_DIR;
    private final Uri tree;
    private final ContentResolver resolver;
    private final String rootId;
    private final Map<String,Map<String,Entry>> cache=new HashMap<>();
    private static final class Entry {
        final String id,mime;
        Entry(String id,String mime){this.id=id;this.mime=mime;}
    }
    public GtaMapSafSource(Context context,Uri selectedFolder) {
        if(context==null||selectedFolder==null)throw new IllegalArgumentException("Choose GTA folder");
        tree=selectedFolder;
        resolver=context.getApplicationContext().getContentResolver();
        rootId=DocumentsContract.getTreeDocumentId(tree);
    }
    private Map<String,Entry> children(String parent) throws IOException {
        Map<String,Entry> cached=cache.get(parent);
        if(cached!=null)return cached;
        Map<String,Entry> entries=new HashMap<>();
        Uri children=DocumentsContract.buildChildDocumentsUriUsingTree(tree,parent);
        String[] columns={DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE};
        try(Cursor cur=resolver.query(children,columns,null,null,null)){
            if(cur==null)throw new IOException("Folder listing unavailable");
            int total=0;
            while(cur.moveToNext()){
                if(++total>10000)throw new IOException("Directory too large");
                String id=cur.getString(0),name=cur.getString(1),mime=cur.getString(2);
                if(id!=null&&name!=null&&mime!=null)
                    entries.put(name.toLowerCase(Locale.ROOT),new Entry(id,mime));
            }
        }catch(SecurityException|IllegalArgumentException e){
            throw new IOException("Access denied to selected GTA folder",e);
        }
        if(cache.size()<800)cache.put(parent,entries);
        return entries;
    }
    public Reader openManifest() throws IOException {return openGameFile("data/gta.dat");}
    @Override public Reader open(String name) throws IOException {
        return openGameFile(GtaMapPlacementIndex.normalizeGamePath(name));
    }
    private Reader openGameFile(String path) throws IOException {
        String[] parts=path.split("/");
        String parent=rootId;
        for(int i=0;i<parts.length;i++){
            Entry e=children(parent).get(parts[i].toLowerCase(Locale.ROOT));
            if(e==null)throw new IOException("Missing GTA file: "+path);
            if(i<parts.length-1){
                if(!DIRECTORY.equals(e.mime))throw new IOException("Expected folder: "+path);
                parent=e.id;
                continue;
            }
            if(DIRECTORY.equals(e.mime))throw new IOException("Expected file: "+path);
            Uri uri=DocumentsContract.buildDocumentUriUsingTree(tree,e.id);
            try{
                InputStream stream=resolver.openInputStream(uri);
                if(stream==null)throw new IOException("GTA file could not be opened: "+path);
                return new InputStreamReader(stream,StandardCharsets.ISO_8859_1);
            }catch(SecurityException ex){
                throw new IOException("GTA file read permission denied: "+path,ex);
            }
        }
        throw new IOException("Empty GTA path");
    }
}