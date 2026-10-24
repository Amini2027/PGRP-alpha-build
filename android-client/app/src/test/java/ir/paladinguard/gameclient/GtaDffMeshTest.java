package ir.paladinguard.gameclient;

import org.junit.Test;
import static org.junit.Assert.*;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

public final class GtaDffMeshTest {
    private static final class Chunks {
        final ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        void write(int value){bytes.write(value&255);}
        void int32(int value) {for(int i=0;i<4;i++)write(value>>>(i*8));}
        void f32(float value){int32(Float.floatToIntBits(value));}
        void values(byte[] value){bytes.write(value,0,value.length);}
        void chunk(int id,byte[] raw) {
            int32(id);int32(raw.length);int32(0x1803FFFF);values(raw);
        }
        byte[] take(){return bytes.toByteArray();}
    }
    private static byte[] dff(boolean invalidTriangle) {
        Chunks geoHeader=new Chunks();
        geoHeader.int32(0); // no UV, no prelit; non-native
        geoHeader.int32(1); // one triangle
        geoHeader.int32(3); // 3 vertices
        geoHeader.int32(1); // one morph
        geoHeader.write(0);geoHeader.write(0);
        geoHeader.write(invalidTriangle?99:2);geoHeader.write(0); // index b
        geoHeader.write(0);geoHeader.write(0); // material ID
        geoHeader.write(1);geoHeader.write(0); // index c
        for(int i=0;i<4;i++)geoHeader.f32(0); // sphere xyz radius
        geoHeader.int32(1);geoHeader.int32(0); // has vertices, no normals
        geoHeader.f32(-1);geoHeader.f32(0);geoHeader.f32(0);
        geoHeader.f32(1);geoHeader.f32(0);geoHeader.f32(0);
        geoHeader.f32(0);geoHeader.f32(0);geoHeader.f32(1);
        Chunks geom=new Chunks();
        geom.chunk(1,geoHeader.take());
        Chunks list=new Chunks();
        Chunks listCount=new Chunks();
        listCount.int32(1);
        list.chunk(1,listCount.take());
        list.chunk(0x0f,geom.take());
        Chunks clump=new Chunks();
        clump.chunk(0x1a,list.take());
        Chunks root=new Chunks();
        root.chunk(0x10,clump.take());
        return root.take();
    }
    @Test public void readsFirstActualDffMeshAndTransformsZUp() throws Exception {
        GtaDffMesh m=GtaDffMesh.parse("street.dff",dff(false));
        assertEquals("street.dff",m.name);
        assertEquals(3,m.originalVertices);
        assertEquals(1,m.originalTriangles);
        assertEquals(18,m.triangles.length);
        for(float x:m.triangles)assertTrue(Float.isFinite(x));
    }
    @Test(expected=IOException.class)public void rejectsIndexPastVertices() throws Exception{
        GtaDffMesh.parse("bad.dff",dff(true));
    }
    @Test(expected=IOException.class)public void rejectsTruncatedChunk() throws Exception{
        byte[] b=dff(false);
        b[4]=(byte)255; // outer chunk exceeds source
        GtaDffMesh.parse("bad.dff",b);
    }
    @Test public void readsDffEntryFromActualImgIndexStructure() throws Exception{
        byte[] d=dff(false),img=new byte[4096];
        ByteBuffer header=ByteBuffer.wrap(img).order(ByteOrder.LITTLE_ENDIAN);
        img[0]='V';img[1]='E';img[2]='R';img[3]='2';
        header.putInt(4,1);
        header.putInt(8,1);
        header.putShort(12,(short)1);header.putShort(14,(short)1);
        byte[] name="sample.dff".getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(name,0,img,16,name.length);
        System.arraycopy(d,0,img,2048,d.length);
        GtaBinaryIplIndex.RandomReader input=new GtaBinaryIplIndex.RandomReader(){
            @Override public long length(){return img.length;}
            @Override public void read(long at,byte[] target,int off,int count) throws IOException{
                if(at<0||at+count>img.length)throw new IOException("bad offset");
                System.arraycopy(img,(int)at,target,off,count);
            }
        };
        GtaDffArchive.Result r=GtaDffArchive.firstSupported(input);
        assertEquals("sample.dff",r.mesh.name);
        assertEquals(1,r.mesh.originalTriangles);
        assertEquals(1,r.examined);
    }
}