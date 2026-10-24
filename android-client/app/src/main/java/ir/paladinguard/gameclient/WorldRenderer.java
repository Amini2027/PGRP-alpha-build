package ir.paladinguard.gameclient;

import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.opengl.Matrix;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.Arrays;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * Standalone OpenGL ES 2.0 client world runtime. All geometry is original
 * procedural demo geometry; it is NOT an import of GTA's proprietary map.
 * Future runtime: licensed asset parser, vehicle physics, remote entities.
 */
public final class WorldRenderer implements GLSurfaceView.Renderer {
    private static final String VERTEX =
        "uniform mat4 uMvp; attribute vec3 aPosition; attribute vec3 aColor;"
        +"varying vec3 vColor; void main(){vColor=aColor;gl_Position=uMvp*vec4(aPosition,1.0);}";
    private static final String FRAGMENT =
        "precision mediump float; varying vec3 vColor;"
        +"void main(){gl_FragColor=vec4(vColor,1.0);}";

    private final float[] projection=new float[16];
    private final float[] view=new float[16];
    private final float[] mvp=new float[16];
    private final WorldMath.Pose pose=new WorldMath.Pose(0f,1f,12f);
    private volatile float moveHorizontal;
    private volatile float moveForward;
    private long lastFrameNanos;
    private FloatBuffer vertices;
    private int vertexCount;
    private int program;
    private int positionAttribute,colorAttribute,mvpUniform;

    public interface PositionObserver {
        void onPosition(float x,float z,float yaw);
    }
    private final PositionObserver observer;
    private long lastObserve;

    public WorldRenderer(PositionObserver observer) { this.observer=observer; }

    public void setMovement(float strafe,float forward) {
        moveHorizontal=WorldMath.clamp(strafe,-1f,1f);
        moveForward=WorldMath.clamp(forward,-1f,1f);
    }

    public synchronized void turn(float dx,float dy) {
        WorldMath.turn(pose,dx,dy,0.004f);
    }

    public synchronized void reset() {
        pose.x=0f;pose.y=1f;pose.z=12f;
        pose.yaw=pose.pitch=0f;
    }

    public synchronized void sprintStep() {
        float radians=pose.yaw;
        pose.x=WorldMath.clamp(pose.x+(float)Math.sin(radians)*2f,-169f,169f);
        pose.z=WorldMath.clamp(pose.z-(float)Math.cos(radians)*2f,-169f,169f);
    }

    private static int compile(int type,String source) {
        int shader=GLES20.glCreateShader(type);
        if(shader==0)throw new IllegalStateException("GLES shader allocation failed");
        GLES20.glShaderSource(shader,source);
        GLES20.glCompileShader(shader);
        int[] result=new int[1];
        GLES20.glGetShaderiv(shader,GLES20.GL_COMPILE_STATUS,result,0);
        if(result[0]==0){
            String error=GLES20.glGetShaderInfoLog(shader);
            GLES20.glDeleteShader(shader);
            throw new IllegalStateException("shader compilation: "+error);
        }
        return shader;
    }

    @Override public void onSurfaceCreated(GL10 gl,EGLConfig config) {
        GLES20.glClearColor(.035f,.065f,.11f,1f);
        GLES20.glEnable(GLES20.GL_DEPTH_TEST);
        GLES20.glDepthFunc(GLES20.GL_LEQUAL);
        GLES20.glDisable(GLES20.GL_CULL_FACE);
        int vs=compile(GLES20.GL_VERTEX_SHADER,VERTEX);
        int fs=compile(GLES20.GL_FRAGMENT_SHADER,FRAGMENT);
        program=GLES20.glCreateProgram();
        GLES20.glAttachShader(program,vs);
        GLES20.glAttachShader(program,fs);
        GLES20.glLinkProgram(program);
        int[] linked=new int[1];
        GLES20.glGetProgramiv(program,GLES20.GL_LINK_STATUS,linked,0);
        GLES20.glDeleteShader(vs);
        GLES20.glDeleteShader(fs);
        if(linked[0]==0)throw new IllegalStateException(GLES20.glGetProgramInfoLog(program));
        positionAttribute=GLES20.glGetAttribLocation(program,"aPosition");
        colorAttribute=GLES20.glGetAttribLocation(program,"aColor");
        mvpUniform=GLES20.glGetUniformLocation(program,"uMvp");
        Geometry geometry=buildDistrict();
        float[] array=geometry.toArray();
        vertexCount=array.length/6;
        ByteBuffer bytes=ByteBuffer.allocateDirect(array.length*Float.BYTES).order(ByteOrder.nativeOrder());
        vertices=bytes.asFloatBuffer();
        vertices.put(array).position(0);
        lastFrameNanos=System.nanoTime();
    }

    @Override public void onSurfaceChanged(GL10 gl,int width,int height) {
        GLES20.glViewport(0,0,width,height);
        Matrix.perspectiveM(projection,0,67f,(float)width/Math.max(1,height),0.12f,380f);
    }

    @Override public void onDrawFrame(GL10 gl) {
        long now=System.nanoTime();
        float dt=lastFrameNanos==0?0f:(now-lastFrameNanos)/1_000_000_000f;
        lastFrameNanos=now;
        final float eyeX,eyeY,eyeZ,forwardX,forwardY,forwardZ,yaw;
        synchronized(this) {
            WorldMath.step(pose,moveHorizontal,moveForward,dt,5.6f);
            yaw=pose.yaw;
            eyeX=pose.x;
            eyeY=pose.y+1.6f;
            eyeZ=pose.z;
            float cp=(float)Math.cos(pose.pitch);
            forwardX=(float)Math.sin(yaw)*cp;
            forwardY=(float)Math.sin(pose.pitch);
            forwardZ=-(float)Math.cos(yaw)*cp;
        }
        Matrix.setLookAtM(view,0,eyeX,eyeY,eyeZ,
            eyeX+forwardX,eyeY+forwardY,eyeZ+forwardZ,0f,1f,0f);
        Matrix.multiplyMM(mvp,0,projection,0,view,0);
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT|GLES20.GL_DEPTH_BUFFER_BIT);
        GLES20.glUseProgram(program);
        GLES20.glUniformMatrix4fv(mvpUniform,1,false,mvp,0);
        vertices.position(0);
        GLES20.glVertexAttribPointer(positionAttribute,3,GLES20.GL_FLOAT,false,6*Float.BYTES,vertices);
        vertices.position(3);
        GLES20.glVertexAttribPointer(colorAttribute,3,GLES20.GL_FLOAT,false,6*Float.BYTES,vertices);
        GLES20.glEnableVertexAttribArray(positionAttribute);
        GLES20.glEnableVertexAttribArray(colorAttribute);
        GLES20.glDrawArrays(GLES20.GL_TRIANGLES,0,vertexCount);
        GLES20.glDisableVertexAttribArray(positionAttribute);
        GLES20.glDisableVertexAttribArray(colorAttribute);
        if(now-lastObserve>500_000_000L){
            lastObserve=now;
            if(observer!=null)observer.onPosition(eyeX,eyeZ,yaw);
        }
    }

    private static Geometry buildDistrict(){
        Geometry g=new Geometry();
        // Flat terrain with generated roads: original artwork, no Rockstar assets.
        g.quad(-185f,-.12f,-185f, 185f,-.12f,-185f,
            185f,-.12f,185f,-185f,-.12f,185f,.085f,.18f,.16f);
        // Orthogonal city street network, intersections every 24 world units.
        for(int v=-168;v<=168;v+=24){
            g.quad(v-3f,-.09f,-179f,v+3f,-.09f,-179f,
                v+3f,-.09f,179f,v-3f,-.09f,179f,.18f,.205f,.245f);
            g.quad(-179f,-.08f,v-3f,179f,-.08f,v-3f,
                179f,-.08f,v+3f,-179f,-.08f,v+3f,.18f,.205f,.245f);
            for(int mark=-170;mark<=170;mark+=11){
                if(Math.abs(mark-v)<6)continue;
                g.quad(v-.06f,-.064f,mark,v+.06f,-.064f,mark,
                    v+.06f,-.064f,mark+4,v-.06f,-.064f,mark+4,.92f,.72f,.33f);
                g.quad(mark,-.063f,v-.06f,mark+4,-.063f,v-.06f,
                    mark+4,-.063f,v+.06f,mark,-.063f,v+.06f,.92f,.72f,.33f);
            }
        }
        // Buildings in blocks between roads; variation is deterministic.
        for(int ix=-6;ix<=6;ix++){
            for(int iz=-6;iz<=6;iz++){
                float x=ix*24+12f;
                float z=iz*24+12f;
                float height=4.8f+((Math.abs(ix*11+iz*29+51)%9))*2.25f;
                float shade=(Math.abs(ix*37+iz*17)%6)*.022f;
                g.box(x,-.07f,z,13f,height,13f,
                    .19f+shade,.27f+shade,.32f+shade);
                // Rooftop structures add depth and scale.
                if((Math.abs(ix*7+iz*11)%3)==0)
                    g.box(x+2f,height-.07f,z-2f,3.5f,2.7f,3.5f,.31f,.36f,.4f);
            }
        }
        // Landmark/spawn plaza
        g.box(0f,-.06f,0f,5.0f,.16f,5f,.76f,.61f,.34f);
        g.box(0f,.08f,0f,1.1f,4.3f,1.1f,.56f,.74f,.77f);
        return g;
    }

    /** Each vertex = position xyz, RGB, baked lighting on the faces. */
    private static final class Geometry {
        private float[] floats=new float[16384];
        private int count;
        private void f(float value){
            if(count==floats.length)floats=Arrays.copyOf(floats,floats.length*2);
            floats[count++]=value;
        }
        private void vertex(float x,float y,float z,float r,float g,float b) {
            f(x);f(y);f(z);f(r);f(g);f(b);
        }
        private void tri(float[] a,float[] b,float[] c,float r,float g,float bl){
            vertex(a[0],a[1],a[2],r,g,bl);
            vertex(b[0],b[1],b[2],r,g,bl);
            vertex(c[0],c[1],c[2],r,g,bl);
        }
        private void quad(float ax,float ay,float az,float bx,float by,float bz,
                          float cx,float cy,float cz,float dx,float dy,float dz,
                          float r,float g,float b) {
            float[] a={ax,ay,az},p={bx,by,bz},c={cx,cy,cz},d={dx,dy,dz};
            tri(a,p,c,r,g,b);tri(a,c,d,r,g,b);
        }
        private void box(float x,float base,float z,float w,float h,float d,float r,float g,float b){
            float l=x-w/2f,rr=x+w/2f,n=z-d/2f,f=z+d/2f,t=base+h;
            quad(l,t,n,rr,t,n,rr,t,f,l,t,f,r*1.23f,g*1.23f,b*1.23f);
            quad(l,base,n,rr,base,n,rr,t,n,l,t,n,r*.78f,g*.78f,b*.78f);
            quad(rr,base,f,l,base,f,l,t,f,rr,t,f,r,g,b);
            quad(l,base,f,l,base,n,l,t,n,l,t,f,r*.61f,g*.61f,b*.61f);
            quad(rr,base,n,rr,base,f,rr,t,f,rr,t,n,r*.87f,g*.87f,b*.87f);
        }
        private float[] toArray(){return Arrays.copyOf(floats,count);}
    }
}
