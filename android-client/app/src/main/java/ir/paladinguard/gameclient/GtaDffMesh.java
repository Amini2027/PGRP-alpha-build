package ir.paladinguard.gameclient;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/**
 * Read-only, bounded RenderWare GTA San Andreas PC DFF parser.
 * Accepts a simple non-native geometry in a RW 3.6 CLUMP. Extracts ORIGINAL
 * triangle vertices (no models/texture assets embedded in the application).
 *
 * Preview is a single local asset only: no frame hierarchy, materials, TXD,
 * vertex skinning or gameplay collision yet. Invalid meshes never reach GL.
 */
public final class GtaDffMesh {
    private static final int ROOT_CLUMP=0x10, GEOMETRY_LIST=0x1a, GEOMETRY=0x0f, RW_STRUCT=1;
    private static final int MAX_BYTES=2*1024*1024,MAX_VERTICES=50_000,MAX_TRIANGLES=50_000;
    public final String name;
    public final float[] triangles; // interleaved RGB XYZ for actual mesh triangles
    public final int originalVertices,originalTriangles;
    GtaDffMesh(String name,float[] triangles,int vertices,int faces){
        this.name=name;this.triangles=triangles;
        originalVertices=vertices;originalTriangles=faces;
    }
    static int u32(byte[] a,int at){return ByteBuffer.wrap(a,at,4).order(ByteOrder.LITTLE_ENDIAN).getInt();}
    static int u16(byte[] a,int at){return (a[at]&255)|((a[at+1]&255)<<8);}
    static float f32(byte[] a,int at){return Float.intBitsToFloat(u32(a,at));}
    static long u32Long(byte[] a,int at){return Integer.toUnsignedLong(u32(a,at));}
    static int end(byte[] a,int pos,int limit) throws IOException {
        if(pos<0||pos>limit-12)throw new IOException("Short RenderWare chunk");
        long len=u32Long(a,pos+4);
        if(len>limit-pos-12)throw new IOException("Chunk exceeds parent bounds");
        return pos+12+(int)len;
    }
    public static GtaDffMesh parse(String filename,byte[] bytes) throws IOException {
        if(bytes==null||bytes.length<48||bytes.length>MAX_BYTES)
            throw new IOException("DFF size not supported");
        // A DFF may start with a UV animation dictionary root before CLUMP.
        for(int cursor=0;cursor<=bytes.length-12;){
            int chunkEnd=end(bytes,cursor,bytes.length);
            if(u32(bytes,cursor)==ROOT_CLUMP){
                return clump(filename,bytes,cursor+12,chunkEnd);
            }
            cursor=chunkEnd;
        }
        throw new IOException("No DFF clump root");
    }
    private static GtaDffMesh clump(String name,byte[] b,int begin,int end) throws IOException {
        for(int pos=begin;pos<=end-12;){
            int next=end(b,pos,end);
            if(u32(b,pos)==GEOMETRY_LIST) {
                int head=pos+12;
                if(head+16>next||u32(b,head)!=RW_STRUCT)
                    throw new IOException("No geometry list struct");
                int headEnd=end(b,head,next);
                if(head+16>headEnd)throw new IOException("Short geometry list");
                int count=u32(b,head+12);
                if(count<1||count>100)throw new IOException("Invalid geometry count");
                int geo=headEnd;
                if(geo+12>next||u32(b,geo)!=GEOMETRY)
                    throw new IOException("Unsupported geometry list");
                int geoEnd=end(b,geo,next);
                return geometry(name,b,geo+12,geoEnd);
            }
            pos=next;
        }
        throw new IOException("No geometry list in clump");
    }
    private static GtaDffMesh geometry(String name,byte[] b,int start,int end) throws IOException {
        if(start+12>end||u32(b,start)!=RW_STRUCT)
            throw new IOException("No geometry struct");
        int sectionEnd=end(b,start,end);
        int data=start+12;
        if(data+16>sectionEnd)throw new IOException("Short geometry header");
        int flags=u32(b,data);
        int countFaces=u32(b,data+4);
        int countVerts=u32(b,data+8);
        int morphCount=u32(b,data+12);
        if((flags & 0x01000000)!=0)throw new IOException("Native geometry unsupported");
        if(countFaces<1||countFaces>MAX_TRIANGLES||countVerts<3||countVerts>MAX_VERTICES
           ||morphCount<1||morphCount>16)
            throw new IOException("Geometry bounds exceeded");
        int cursor=data+16;
        // Non-native geometry contains optional pre-3.4 light float triplet.
        int version=u32(b,start+8);
        // RenderWare encoded library versions > 0xFFFF have bitpacked values.
        int effectiveVersion=((version & 0xFFFF0000)!=0)
            ? (((version>>14)&0x3FF00)+0x30000 | ((version>>16)&0x3F))
            : version;
        if(effectiveVersion<0x34000)cursor=checked(cursor,12,sectionEnd);
        if((flags&0x8)!=0)cursor=checked(cursor,4L*countVerts,sectionEnd);
        int layers=(flags>>16)&255;
        if(layers==0&&(flags&0x4)!=0)layers=1;
        if(layers>8)throw new IOException("Too many UV sets");
        cursor=checked(cursor,8L*layers*countVerts,sectionEnd);
        int trianglePos=cursor;
        cursor=checked(cursor,8L*countFaces,sectionEnd);
        int vertexPos=-1;
        for(int morph=0;morph<morphCount;morph++){
            if(cursor+24>sectionEnd)throw new IOException("Short DFF morph target");
            int hasVertices=u32(b,cursor+16),hasNormals=u32(b,cursor+20);
            cursor+=24;
            if(hasVertices!=0){
                if(morph==0)vertexPos=cursor;
                cursor=checked(cursor,12L*countVerts,sectionEnd);
            }
            if(hasNormals!=0)cursor=checked(cursor,12L*countVerts,sectionEnd);
        }
        if(vertexPos<0)throw new IOException("Geometry does not include vertex positions");
        // Validate all input before allocation and scale for isolated GL preview.
        float[] positions=new float[countVerts*3];
        float minX=Float.POSITIVE_INFINITY,maxX=Float.NEGATIVE_INFINITY;
        float minY=Float.POSITIVE_INFINITY,maxY=Float.NEGATIVE_INFINITY;
        float minZ=Float.POSITIVE_INFINITY,maxZ=Float.NEGATIVE_INFINITY;
        for(int i=0;i<countVerts;i++){
            float x=f32(b,vertexPos+i*12),y=f32(b,vertexPos+i*12+4),z=f32(b,vertexPos+i*12+8);
            if(!Float.isFinite(x)||!Float.isFinite(y)||!Float.isFinite(z)||
              Math.abs(x)>100000||Math.abs(y)>100000||Math.abs(z)>100000)
                throw new IOException("Invalid DFF vertex");
            positions[i*3]=x;positions[i*3+1]=y;positions[i*3+2]=z;
            minX=Math.min(minX,x);maxX=Math.max(maxX,x);
            minY=Math.min(minY,y);maxY=Math.max(maxY,y);
            minZ=Math.min(minZ,z);maxZ=Math.max(maxZ,z);
        }
        float size=Math.max(.001f,Math.max(maxX-minX,Math.max(maxY-minY,maxZ-minZ)));
        float centerX=(minX+maxX)/2f,centerY=(minY+maxY)/2f,centerZ=(minZ+maxZ)/2f;
        // World is Z-up in GTA; preview GL uses Y-up.
        float[] render=new float[countFaces*3*6];
        for(int i=0;i<countFaces;i++){
            int at=trianglePos+i*8;
            int a=u16(b,at),c=u16(b,at+2),d=u16(b,at+6);
            if(a>=countVerts||c>=countVerts||d>=countVerts)
                throw new IOException("Triangle references invalid vertex");
            int[] idx={a,c,d};
            float tint=.48f+(i%11)*.025f;
            for(int v=0;v<3;v++){
                int offset=(i*3+v)*6,atVert=idx[v]*3;
                render[offset]=(positions[atVert]-centerX)/size*3.0f;
                render[offset+1]=(positions[atVert+2]-centerZ)/size*3.0f;
                render[offset+2]=-(positions[atVert+1]-centerY)/size*3.0f;
                render[offset+3]=tint*.65f;
                render[offset+4]=tint*.89f;
                render[offset+5]=tint;
            }
        }
        return new GtaDffMesh(name,render,countVerts,countFaces);
    }
    private static int checked(int pos,long count,int end) throws IOException{
        if(count<0||count>end-pos)throw new IOException("DFF struct section truncated");
        return pos+(int)count;
    }
}
