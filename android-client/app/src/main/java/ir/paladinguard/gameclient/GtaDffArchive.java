package ir.paladinguard.gameclient;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Scans the user's GTA SA IMG archive for a small, valid RenderWare DFF.
 * Reads only individual directory entries and bounded DFF data; no full
 * gta3.img in memory, network requests or data distribution.
 */
public final class GtaDffArchive {
    public static final class Result {
        public final GtaDffMesh mesh;
        public final int examined,candidates,rejected;
        public final String firstError;
        Result(GtaDffMesh mesh,int examined,int candidates,int rejected,String firstError){
            this.mesh=mesh;this.examined=examined;this.candidates=candidates;
            this.rejected=rejected;this.firstError=firstError;
        }
    }
    private static final int SECTOR=2048,MAX_FILES=200000,MAX_ATTEMPTS=160,MAX_DFF=2*1024*1024;
    private GtaDffArchive(){}
    private static long u32(byte[] b,int at){
        return Integer.toUnsignedLong(GtaDffMesh.u32(b,at));
    }
    private static int u16(byte[] b,int at){return GtaDffMesh.u16(b,at);}
    static String ascii(byte[] b,int from,int n){
        int actual=0;while(actual<n&&b[from+actual]!=0)actual++;
        return new String(b,from,actual,StandardCharsets.US_ASCII).trim().toLowerCase(Locale.ROOT);
    }
    private static final class Candidate {
        final String name;
        final long start,size;
        Candidate(String name,long start,long size){this.name=name;this.start=start;this.size=size;}
    }
    public static Result firstSupported(GtaBinaryIplIndex.RandomReader file) throws IOException {
        long length=file.length();
        if(length<SECTOR)throw new IOException("IMG archive too small");
        byte[] head=new byte[8];file.read(0,head,0,8);
        if(head[0]!='V'||head[1]!='E'||head[2]!='R'||head[3]!='2')
            throw new IOException("Unsupported IMG header");
        long count=u32(head,4);
        if(count<1||count>MAX_FILES||count*32L+8>length)
            throw new IOException("Invalid IMG index");
        // Read directory once to avoid thousands of SAF-provider transactions.
        byte[] index=new byte[(int)(count*32L)];
        file.read(8,index,0,index.length);
        List<Candidate> candidates=new ArrayList<>();
        for(int i=0;i<count;i++){
            int p=i*32;
            String name=ascii(index,p+8,24);
            if(!name.endsWith(".dff"))continue;
            long start=u32(index,p)*SECTOR;
            long sec=u16(index,p+6);
            if(sec==0)sec=u16(index,p+4);
            long size=sec*SECTOR;
            if(size<64||size>MAX_DFF||start>length-size)continue;
            candidates.add(new Candidate(name,start,size));
        }
        // Prefer relatively small buildings and static props suitable for a
        // first preview; avoid huge animation-heavy DFFs and cap latency.
        candidates.sort((a,b)->Long.compare(a.size,b.size));
        int tried=0,rejected=0;
        String firstError=null;
        for(Candidate candidate:candidates){
            if(tried>=MAX_ATTEMPTS)break;
            tried++;
            try{
                byte[] bytes=new byte[(int)candidate.size];
                file.read(candidate.start,bytes,0,bytes.length);
                GtaDffMesh mesh=GtaDffMesh.parse(candidate.name,bytes);
                return new Result(mesh,tried,candidates.size(),rejected,firstError);
            }catch(IOException exception){
                rejected++;
                if(firstError==null)firstError=candidate.name+": "+exception.getMessage();
            }
        }
        throw new IOException("No supported static DFF among "+tried+
            " candidates. "+(firstError==null?"Missing readable DFF":firstError));
    }
}
