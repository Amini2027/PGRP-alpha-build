package ir.paladinguard.gameclient;

import org.junit.Test;
import static org.junit.Assert.*;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

public class GtaImgIndexTest {
    private static void u16(byte[] b,int off,int value){
        b[off]=(byte)value;b[off+1]=(byte)(value>>8);
    }
    private static void u32(byte[] b,int off,long value){
        b[off]=(byte)value;b[off+1]=(byte)(value>>8);
        b[off+2]=(byte)(value>>16);b[off+3]=(byte)(value>>24);
    }
    private static byte[] img(String name) {
        byte[] b=new byte[6144];
        b[0]='V';b[1]='E';b[2]='R';b[3]='2';
        u32(b,4,1);
        u32(b,8,1); // sector 1 -> 2048 bytes
        u16(b,12,1);
        u16(b,14,1);
        byte[] n=name.getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(n,0,b,16,n.length);
        return b;
    }
    @Test public void correctDirectoryReadsOffsetsSizesAndModelNames() throws Exception {
        GtaImgIndex.Result result=GtaImgIndex.parse(new ByteArrayInputStream(img("land01.dff")),6144);
        assertEquals(1,result.count);
        assertEquals("land01.dff",result.samples.get(0).name);
        assertEquals(2048L,result.samples.get(0).offsetBytes);
        assertEquals(2048L,result.samples.get(0).sizeBytes);
    }
    @Test(expected=IOException.class)public void rejectWrongMagic() throws Exception {
        byte[] b=img("land01.dff");b[0]='A';
        GtaImgIndex.parse(new ByteArrayInputStream(b),b.length);
    }
    @Test(expected=IOException.class)public void rejectUnboundedEntryCount() throws Exception {
        byte[] b=img("land01.dff");u32(b,4,200001);
        GtaImgIndex.parse(new ByteArrayInputStream(b),b.length);
    }
    @Test(expected=IOException.class)public void rejectOutOfBoundsEntry() throws Exception {
        byte[] b=img("land01.dff");u32(b,8,99);
        GtaImgIndex.parse(new ByteArrayInputStream(b),b.length);
    }
    @Test(expected=IOException.class)public void rejectTruncatedInput() throws Exception {
        byte[] b=img("land01.dff");
        GtaImgIndex.parse(new ByteArrayInputStream(new byte[]{'V','E','R','2'}),b.length);
    }
    @Test(expected=IOException.class)public void rejectDangerousModelName() throws Exception {
        byte[] b=img("../invalid.dff");
        GtaImgIndex.parse(new ByteArrayInputStream(b),b.length);
    }
    @Test public void resourceSizeFallbackToStreamingSize() throws Exception {
        byte[] b=img("model.txd");u16(b,14,0);
        GtaImgIndex.Result result=GtaImgIndex.parse(new ByteArrayInputStream(b),b.length);
        assertEquals(2048L,result.samples.get(0).sizeBytes);
    }
}
