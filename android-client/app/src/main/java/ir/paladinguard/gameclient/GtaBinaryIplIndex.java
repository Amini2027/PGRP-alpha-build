package ir.paladinguard.gameclient;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * Safe, read-only parser for GTA SA IMG VER2 streaming IPL entries.
 *
 * Binary IPL layout: 76 byte "bnry" header; uint32 count at +4, offset of
 * 40-byte inst records at +28; each instance: position xyz, quaternion xyzw,
 * modelId, flags, lodIndex (all little-endian). No Rockstar data is copied
 * into the APK. Parsing is random-access and memory-bounded on Android 9.
 */
public final class GtaBinaryIplIndex {
    private static final int SECTOR=2048,DIR_ENTRY=32,HEADER=76,INSTANCE=40;
    private static final int MAX_DIRECTORY=200_000,MAX_BINARY_FILES=1000;
    private static final int MAX_INSTANCES_PER_FILE=60_000,MAX_SAMPLES=12_000;
    public interface RandomReader {
        long length() throws IOException;
        void read(long position,byte[] data,int from,int count) throws IOException;
    }
    public static final class Result {
        public final int binaryFiles,parsedFiles,instances,nearbyOutside,rejected;
        public final List<GtaMapPlacementIndex.Instance> visibleSamples;
        public final List<String> errors;
        Result(int binaryFiles,int parsedFiles,int instances,int nearbyOutside,
               int rejected,List<GtaMapPlacementIndex.Instance> samples,List<String> errors) {
            this.binaryFiles=binaryFiles;
            this.parsedFiles=parsedFiles;
            this.instances=instances;
            this.nearbyOutside=nearbyOutside;
            this.rejected=rejected;
            visibleSamples=Collections.unmodifiableList(new ArrayList<>(samples));
            this.errors=Collections.unmodifiableList(new ArrayList<>(errors));
        }
    }
    private static final class Ipl {
        final String name;
        final long start,bytes;
        Ipl(String n,long st,long len){name=n;start=st;bytes=len;}
    }
    private GtaBinaryIplIndex(){}
    private static int int32(byte[] b,int i) {
        return (b[i]&255)|((b[i+1]&255)<<8)|((b[i+2]&255)<<16)|((b[i+3]&255)<<24);
    }
    private static int u16(byte[] b,int i){return (b[i]&255)|((b[i+1]&255)<<8);}
    private static String name(byte[] b,int i,int max) {
        int len=0;
        while(len<max&&b[i+len]!=0)len++;
        return new String(b,i,len,StandardCharsets.US_ASCII).trim().toLowerCase(Locale.ROOT);
    }
    private static boolean finite(float... v) {
        for(float f:v)if(!Float.isFinite(f))return false;
        return true;
    }
    public static Result scan(RandomReader file) throws IOException {
        if(file==null)throw new IllegalArgumentException("Missing IMG source");
        long length=file.length();
        if(length<SECTOR)throw new IOException("IMG file truncated");
        byte[] head=new byte[8];file.read(0,head,0,8);
        if(head[0]!='V'||head[1]!='E'||head[2]!='R'||head[3]!='2')
            throw new IOException("Unsupported IMG (expected VER2)");
        long directoryCount=Integer.toUnsignedLong(int32(head,4));
        if(directoryCount==0||directoryCount>MAX_DIRECTORY ||
            8+directoryCount*DIR_ENTRY>length)
            throw new IOException("Invalid IMG directory");
        ArrayList<Ipl> entries=new ArrayList<>();
        byte[] row=new byte[DIR_ENTRY];
        for(int i=0;i<directoryCount;i++){
            file.read(8L+i*DIR_ENTRY,row,0,row.length);
            String filename=name(row,8,24);
            if(!filename.endsWith(".ipl"))continue;
            if(entries.size()>=MAX_BINARY_FILES)throw new IOException("Too many streaming IPL files");
            long start=Integer.toUnsignedLong(int32(row,0))*SECTOR;
            long streaming=u16(row,4),resource=u16(row,6);
            long size=(resource>0?resource:streaming)*SECTOR;
            if(start<0||size<HEADER||start>length-size)
                throw new IOException("IPL outside IMG: "+filename);
            entries.add(new Ipl(filename,start,size));
        }
        int parsed=0,instances=0,nearby=0,rejected=0;
        ArrayList<GtaMapPlacementIndex.Instance> samples=new ArrayList<>();
        ArrayList<String> errors=new ArrayList<>();
        byte[] record=new byte[INSTANCE],hdr=new byte[HEADER];
        for(Ipl entry:entries){
            try {
                file.read(entry.start,hdr,0,HEADER);
                if(hdr[0]!='b'||hdr[1]!='n'||hdr[2]!='r'||hdr[3]!='y'){
                    if(errors.size()<12)errors.add(entry.name+": not binary IPL");
                    continue;
                }
                long count=Integer.toUnsignedLong(int32(hdr,4));
                long offset=Integer.toUnsignedLong(int32(hdr,28));
                if(count>MAX_INSTANCES_PER_FILE||offset<HEADER||
                   offset>entry.bytes||count>(entry.bytes-offset)/INSTANCE)
                    throw new IOException("Invalid binary instance range");
                parsed++;
                for(int i=0;i<count;i++){
                    file.read(entry.start+offset+(long)i*INSTANCE,record,0,INSTANCE);
                    ByteBuffer b=ByteBuffer.wrap(record).order(ByteOrder.LITTLE_ENDIAN);
                    float x=b.getFloat(),y=b.getFloat(),z=b.getFloat();
                    float qx=b.getFloat(),qy=b.getFloat(),qz=b.getFloat(),qw=b.getFloat();
                    int modelId=b.getInt(),flags=b.getInt(),lod=b.getInt();
                    if(!finite(x,y,z,qx,qy,qz,qw) ||
                       Math.abs(x)>20000||Math.abs(y)>20000||Math.abs(z)>20000||
                       modelId<1||modelId>100000 ||
                       qx*qx+qy*qy+qz*qz+qw*qw<.5f ||
                       qx*qx+qy*qy+qz*qz+qw*qw>1.5f){
                        rejected++;continue;
                    }
                    instances++;
                    // Streaming flags are NOT interpreted as interior ID:
                    // binary IPL instances belong to outdoors sectors.
                    if(Math.abs(x-GtaMapPlacementIndex.CENTER_X)<GtaMapPlacementIndex.PREVIEW_RADIUS
                       && Math.abs(y-GtaMapPlacementIndex.CENTER_Y)<GtaMapPlacementIndex.PREVIEW_RADIUS){
                        nearby++;
                        if(samples.size()<MAX_SAMPLES)
                            samples.add(new GtaMapPlacementIndex.Instance(
                                modelId,0,lod,"binary_"+modelId,x,y,z,qx,qy,qz,qw));
                    }
                }
            }catch(IOException failure){
                if(errors.size()<12)errors.add(entry.name+": "+failure.getMessage());
            }
        }
        return new Result(entries.size(),parsed,instances,nearby,rejected,samples,errors);
    }
}
