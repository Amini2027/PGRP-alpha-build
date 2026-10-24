package ir.paladinguard.gameclient;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Read-only GTA SA PC IMG v2 archive directory validator.
 * Does not redistribute, modify or render copyrighted game content.
 * IMG offsets and streaming sizes are in 2048-byte sectors.
 */
public final class GtaImgIndex {
    public static final int SECTOR_BYTES = 2048;
    public static final int MAX_ENTRIES = 200_000;
    public static final int MAX_SAMPLE_ENTRIES = 8;

    public static final class Sample {
        public final String name;
        public final long offsetBytes;
        public final long sizeBytes;
        public Sample(String name,long offsetBytes,long sizeBytes) {
            this.name=name;this.offsetBytes=offsetBytes;this.sizeBytes=sizeBytes;
        }
    }
    public static final class Result {
        public final int count;
        public final List<Sample> samples;
        public Result(int count,List<Sample> samples) {
            this.count=count;
            this.samples=Collections.unmodifiableList(samples);
        }
    }

    private GtaImgIndex(){}

    private static void readFully(InputStream input, byte[] data, int off, int len) throws IOException {
        int end=off+len;
        while(off<end) {
            int received=input.read(data,off,end-off);
            if(received<0)throw new IOException("IMG v2 directory ended unexpectedly");
            if(received==0) {
                int single=input.read();
                if(single<0)throw new IOException("IMG v2 directory ended unexpectedly");
                data[off++]=(byte)single;
            }else off+=received;
        }
    }
    private static long u32(byte[] b,int off) {
        return (b[off]&255L)|((b[off+1]&255L)<<8)|((b[off+2]&255L)<<16)|((b[off+3]&255L)<<24);
    }
    private static int u16(byte[] b,int off) {
        return (b[off]&255)|((b[off+1]&255)<<8);
    }

    public static Result parse(InputStream in,long archiveBytes) throws IOException {
        if(in==null || archiveBytes<SECTOR_BYTES)throw new IOException("IMG archive too small");
        byte[] header=new byte[8];
        readFully(in,header,0,8);
        String magic=new String(header,0,4,StandardCharsets.US_ASCII);
        if(!"VER2".equals(magic))
            throw new IOException("Unsupported IMG format: expected GTA SA PC VER2");
        long count=u32(header,4);
        if(count<1 || count>MAX_ENTRIES || 8L+count*32L>archiveBytes)
            throw new IOException("Invalid IMG file directory entry count");
        List<Sample> samples=new ArrayList<>();
        byte[] entry=new byte[32];
        for(int i=0;i<count;i++) {
            readFully(in,entry,0,entry.length);
            long offset=u32(entry,0)*SECTOR_BYTES;
            int streaming=u16(entry,4);
            int resource=u16(entry,6);
            long sectors=resource!=0?resource:streaming;
            if(sectors<=0 || offset>=archiveBytes ||
                sectors>(Long.MAX_VALUE-offset)/SECTOR_BYTES ||
                offset+sectors*SECTOR_BYTES>archiveBytes)
                throw new IOException("IMG entry "+i+" extends outside its archive");
            int length=0;
            while(length<24 && entry[8+length]!=0)length++;
            String name=new String(entry,8,length,StandardCharsets.US_ASCII).trim();
            if(name.isEmpty() || name.contains("/") || name.contains("\\") || name.contains(".."))
                throw new IOException("Invalid IMG model name for entry "+i);
            if(samples.size()<MAX_SAMPLE_ENTRIES)samples.add(new Sample(name,offset,sectors*SECTOR_BYTES));
        }
        return new Result((int)count,samples);
    }
}
