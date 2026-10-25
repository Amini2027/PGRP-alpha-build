package ir.paladinguard.gameclient;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Reads local shared vehicle textures from <game>/models/generic/vehicle.txd.
 * The game assets remain on the user's device, read-only. Never embeds or uploads them.
 * RenderWare vehicle materials commonly inherit from this shared dictionary.
 */
public final class GtaSharedVehicleTxd {
    private static final String DIRECTORY=DocumentsContract.Document.MIME_TYPE_DIR;
    private static final int MAX_BYTES=48*1024*1024;
    private GtaSharedVehicleTxd(){}

    public static final class Outcome {
        public final GtaWorldModelLoader.ModelData model;
        public final String detail;
        public final int added;
        Outcome(GtaWorldModelLoader.ModelData data,String info,int n){
            this.model=data;this.detail=info;this.added=n;
        }
    }

    private static String childId(ContentResolver resolver,Uri tree,String parentId,
                                  String wanted,boolean folder) throws IOException {
        Uri childUri=DocumentsContract.buildChildDocumentsUriUsingTree(tree,parentId);
        String[] columns={
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        };
        try(Cursor cursor=resolver.query(childUri,columns,null,null,null)){
            if(cursor==null)throw new IOException("Cannot list GTA directory: "+wanted);
            int seen=0;
            while(cursor.moveToNext()){
                if(++seen>10000)throw new IOException("GTA directory has too many entries");
                String id=cursor.getString(0),name=cursor.getString(1),mime=cursor.getString(2);
                if(name!=null && name.equalsIgnoreCase(wanted) && id!=null){
                    if(folder!=DIRECTORY.equals(mime))
                        throw new IOException(wanted+" is not a "+(folder?"folder":"file"));
                    return id;
                }
            }
        }catch(SecurityException e){throw new IOException("No permission to read GTA folder",e);}
        throw new IOException("Missing models/generic/vehicle.txd component: "+wanted);
    }

    private static byte[] localVehicleTxd(Context context,Uri tree)throws IOException {
        if(context==null||tree==null)throw new IOException("Select GTA root folder in PGRP main screen first");
        ContentResolver resolver=context.getContentResolver();
        String id;
        try {id=DocumentsContract.getTreeDocumentId(tree);}
        catch(Exception e){throw new IOException("Saved GTA folder permission invalid; select folder again",e);}
        for(String part:new String[]{"models","generic"})
            id=childId(resolver,tree,id,part,true);
        id=childId(resolver,tree,id,"vehicle.txd",false);
        Uri uri=DocumentsContract.buildDocumentUriUsingTree(tree,id);
        try(InputStream in=resolver.openInputStream(uri)){
            if(in==null)throw new IOException("Could not open vehicle.txd");
            ByteArrayOutputStream out=new ByteArrayOutputStream();
            byte[] buf=new byte[32768];int n;int total=0;
            while((n=in.read(buf))!=-1){
                if(n==0)continue;
                if(n>MAX_BYTES-total)throw new IOException("vehicle.txd exceeds safe maximum size");
                out.write(buf,0,n);total+=n;
            }
            return out.toByteArray();
        }catch(SecurityException e){throw new IOException("Permission denied to vehicle.txd",e);}
    }

    public static Outcome merge(Context context,Uri gtaRoot,
                  GtaWorldModelLoader.ModelData source)throws IOException {
        if(source==null)throw new IOException("No DFF model to merge");
        if(source.missingMaterialTextures.isEmpty())
            return new Outcome(source,"All referenced textures already present",0);
        byte[] raw=localVehicleTxd(context,gtaRoot);
        List<RenderWareTxd.Texture> shared=
            RenderWareTxd.read(new ByteArrayInputStream(raw));
        Map<String,RenderWareTxd.Texture> merged=new LinkedHashMap<>(source.textureByName);
        int added=0;
        for(RenderWareTxd.Texture texture:shared){
            if(source.missingMaterialTextures.contains(texture.name) && !merged.containsKey(texture.name)){
                // An unsupported raster is still surfaced as a diagnostic instead of silently disappearing.
                merged.put(texture.name,texture);
                added++;
            }
        }
        List<String> missing=new ArrayList<>();
        for(String textureName:source.materials.textureNames)
            if(!merged.containsKey(textureName))missing.add(textureName);
        GtaWorldModelLoader.ModelData enriched=
            new GtaWorldModelLoader.ModelData(source.model,source.txdName,source.dffData,
                   source.materials,source.geometry,merged,missing);
        return new Outcome(enriched,"Shared textures: models/generic/vehicle.txd (found "
                      +added+" of "+source.missingMaterialTextures.size()+")",added);
    }
}
