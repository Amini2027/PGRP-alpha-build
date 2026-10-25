package ir.paladinguard.gameclient;

import org.junit.Test;
import static org.junit.Assert.*;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

public class GtaBinaryIplIndexTest {
    private static byte[] makeImage(int count) {
        byte[] img=new byte[8192];
        ByteBuffer b=ByteBuffer.wrap(img).order(ByteOrder.LITTLE_ENDIAN);
        b.put(0,(byte)'V');b.put(1,(byte)'E');b.put(2,(byte)'R');b.put(3,(byte)'2');
        b.putInt(4,1);
        b.putInt(8,1);b.putShort(12,(short)2);b.putShort(14,(short)2);
        byte[] name="test_stream0.ipl".getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(name,0,img,16,name.length);
        int begin=2048;
        for(int i=0;i<4;i++)img[begin+i]=(byte)"bnry".charAt(i);
        b.putInt(begin+4,count);
        b.putInt(begin+28,76);
        for(int i=0;i<2;i++){
            b.position(begin+76+i*40);
            b.putFloat(i==0?1450f:Float.NaN).putFloat(-1700f)
                .putFloat(18f).putFloat(0f).putFloat(0f).putFloat(0f).putFloat(1f);
            b.putInt(1430+i).putInt(0).putInt(-1);
        }
        return img;
    }
    private static GtaBinaryIplIndex.RandomReader in(byte[] bytes) {
        return new GtaBinaryIplIndex.RandomReader(){
            @Override public long length(){return bytes.length;}
            @Override public void read(long pos,byte[] target,int off,int count) throws IOException{
                if(pos<0||pos+count>bytes.length)throw new IOException("truncated fixture");
                System.arraycopy(bytes,(int)pos,target,off,count);
            }
        };
    }
    @Test public void readsRealFormatBinry40ByteWorldTransforms() throws Exception {
        GtaBinaryIplIndex.Result result=GtaBinaryIplIndex.scan(in(makeImage(2)));
        assertEquals(1,result.binaryFiles);
        assertEquals(1,result.parsedFiles);
        assertEquals(1,result.instances);
        assertEquals(1,result.nearbyOutside);
        assertEquals(1,result.rejected);
        assertEquals(1430,result.visibleSamples.get(0).modelId);
        assertEquals(1450f,result.visibleSamples.get(0).x,1e-4);
        assertEquals(-1700f,result.visibleSamples.get(0).y,1e-4);
        assertEquals(18f,result.visibleSamples.get(0).z,1e-4);
        assertEquals(-1,result.visibleSamples.get(0).lod);
    }
    @Test public void noBinaryIplFilesIsNotAnError() throws Exception {
        byte[] img=makeImage(1);
        for(int i=0;i<24;i++)img[16+i]=0;
        byte[] name="world.dff".getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(name,0,img,16,name.length);
        GtaBinaryIplIndex.Result r=GtaBinaryIplIndex.scan(in(img));
        assertEquals(0,r.binaryFiles);assertEquals(0,r.instances);
    }
    @Test(expected=IOException.class)public void rejectImgDirectoryPastEnd() throws Exception {
        byte[] img=makeImage(1);
        ByteBuffer.wrap(img).order(ByteOrder.LITTLE_ENDIAN).putInt(4,300000);
        GtaBinaryIplIndex.scan(in(img));
    }
    @Test(expected=IOException.class)public void rejectIplOffsetPastArchive() throws Exception {
        byte[] img=makeImage(1);
        ByteBuffer.wrap(img).order(ByteOrder.LITTLE_ENDIAN).putInt(8,10000);
        GtaBinaryIplIndex.scan(in(img));
    }
    @Test public void corruptIplRecordCountIsSkippedButScanningCompletes() throws Exception {
        byte[] img=makeImage(1);
        ByteBuffer.wrap(img).order(ByteOrder.LITTLE_ENDIAN).putInt(2048+4,200000);
        GtaBinaryIplIndex.Result r=GtaBinaryIplIndex.scan(in(img));
        assertEquals(1,r.binaryFiles);assertEquals(0,r.parsedFiles);
        assertFalse(r.errors.isEmpty());
    }
    @Test public void unsupportedIplMagicIsReportedWithoutCrash() throws Exception {
        byte[] img=makeImage(1);img[2048]='X';
        GtaBinaryIplIndex.Result r=GtaBinaryIplIndex.scan(in(img));
        assertEquals(0,r.parsedFiles);
        assertTrue(r.errors.get(0).contains("not binary"));
    }
}
