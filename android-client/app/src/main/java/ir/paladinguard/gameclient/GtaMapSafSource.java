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
    /**
     * User-owned models/gta3.img is examined in place using Android SAF.
     * No whole-archive copying: each binary IPL record is sought via
     * FileChannel on a provider-granted read-only file descriptor.
     */
    public GtaBinaryIplIndex.Result scanBinaryIpl() throws IOException {
        Entry models=children(rootId).get("models");
        if(models==null||!DIRECTORY.equals(models.mime))
            throw new IOException("models folder missing");
        Entry archive=children(models.id).get("gta3.img");
        if(archive==null||DIRECTORY.equals(archive.mime))
            throw new IOException("gta3.img file missing");
        Uri uri=DocumentsContract.buildDocumentUriUsingTree(tree,archive.id);
        try(android.os.ParcelFileDescriptor fd=resolver.openFileDescriptor(uri,"r")){
            if(fd==null)throw new IOException("GTA archive is not readable");
            try(java.io.FileInputStream input=new java.io.FileInputStream(fd.getFileDescriptor())){
                java.nio.channels.FileChannel channel=input.getChannel();
                return GtaBinaryIplIndex.scan(new GtaBinaryIplIndex.RandomReader(){
                    @Override public long length() throws IOException{return channel.size();}
                    @Override public void read(long at,byte[] buf,int off,int count) throws IOException{
                        if(at<0||off<0||count<0||off>buf.length-count)
                            throw new IOException("Invalid IMG offset or read size");
                        java.nio.ByteBuffer destination=java.nio.ByteBuffer.wrap(buf,off,count);
                        while(destination.hasRemaining()){
                            int read=channel.read(destination,at);
                            if(read<=0)throw new IOException("Truncated IMG at "+at);
                            at+=read;
                        }
                    }
                });
            }
        }catch(SecurityException e){
            throw new IOException("Android denied access to GTA archive",e);
        }catch(UnsupportedOperationException e){
            throw new IOException("Storage provider does not support indexed file reads",e);
        }
    }

    /** Preview one real, small static DFF from original local GTA archive.
     * Does not distribute assets, access the network, or load the whole IMG.
     */
    public GtaDffArchive.Result loadRealDff() throws IOException {
        Entry models=children(rootId).get("models");
        if(models==null||!DIRECTORY.equals(models.mime))
            throw new IOException("GTA models directory missing");
        Entry archive=children(models.id).get("gta3.img");
        if(archive==null||DIRECTORY.equals(archive.mime))
            throw new IOException("Missing local gta3.img");
        Uri uri=DocumentsContract.buildDocumentUriUsingTree(tree,archive.id);
        try(android.os.ParcelFileDescriptor fd=resolver.openFileDescriptor(uri,"r")){
            if(fd==null)throw new IOException("GTA archive not readable");
            try(java.io.FileInputStream input=new java.io.FileInputStream(fd.getFileDescriptor())){
                java.nio.channels.FileChannel channel=input.getChannel();
                return GtaDffArchive.firstSupported(new GtaBinaryIplIndex.RandomReader(){
                    @Override public long length() throws IOException{return channel.size();}
                    @Override public void read(long at,byte[] dest,int off,int count) throws IOException{
                        if(at<0||off<0||count<0||off>dest.length-count)
                            throw new IOException("Invalid DFF IMG read");
                        java.nio.ByteBuffer buffer=java.nio.ByteBuffer.wrap(dest,off,count);
                        while(buffer.hasRemaining()){
                            int n=channel.read(buffer,at);
                            if(n<=0)throw new IOException("IMG truncated during DFF read");
                            at+=n;
                        }
                    }
                });
            }
        }catch(SecurityException e){throw new IOException("GTA folder permission denied",e);}
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