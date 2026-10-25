package ir.paladinguard.gameclient;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.opengl.Matrix;
import android.os.Bundle;
import android.view.Gravity;
import android.view.MotionEvent;
import android.widget.FrameLayout;
import android.widget.TextView;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.Locale;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * Dedicated off-world viewer for exactly ONE original GTA DFF mesh.
 * No assumption that displaying one mesh means GTA world streaming is done.
 * Temporary in-process handoff is cleared after consumption; no asset
 * stored inside the APK or sent over the network.
 */
public final class GtaDffPreviewActivity extends Activity {
    private static GtaDffMesh pendingMesh;
    private GLSurfaceView surface;
    public static synchronized void show(Activity from,GtaDffMesh mesh) {
        pendingMesh=mesh;
        from.startActivity(new Intent(from,GtaDffPreviewActivity.class));
    }
    private static synchronized GtaDffMesh take() {
        GtaDffMesh result=pendingMesh;
        pendingMesh=null;
        return result;
    }
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        GtaDffMesh mesh=take();
        if(mesh==null){finish();return;}
        FrameLayout root=new FrameLayout(this);
        root.setBackgroundColor(Color.rgb(8,14,24));
        PreviewRenderer renderer=new PreviewRenderer(mesh);
        surface=new GLSurfaceView(this);
        surface.setEGLContextClientVersion(2);
        surface.setRenderer(renderer);
        surface.setRenderMode(GLSurfaceView.RENDERMODE_CONTINUOUSLY);
        surface.setOnTouchListener((v,event)->{
            switch(event.getActionMasked()){
                case MotionEvent.ACTION_DOWN:
                    renderer.lastX=event.getX();renderer.lastY=event.getY();return true;
                case MotionEvent.ACTION_MOVE:
                    float x=event.getX(),y=event.getY();
                    renderer.turn(x-renderer.lastX,y-renderer.lastY);
                    renderer.lastX=x;renderer.lastY=y;
                    return true;
                default:return true;
            }
        });
        root.addView(surface,new FrameLayout.LayoutParams(-1,-1));
        TextView title=new TextView(this);
        title.setText(String.format(Locale.US,
            "PGRP — REAL GTA DFF  |  %s  |  %d vertices / %d faces\n"+
            "Touch to rotate • untextured single-mesh preview • not the entire city",
            mesh.name,mesh.originalVertices,mesh.originalTriangles));
        title.setTextColor(Color.rgb(240,220,175));
        title.setTextSize(14);
        title.setPadding(24,12,24,12);
        title.setGravity(Gravity.TOP|Gravity.CENTER_HORIZONTAL);
        title.setBackgroundColor(0xDD0A1725);
        FrameLayout.LayoutParams p=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);
        root.addView(title,p);
        setContentView(root);
    }
    @Override protected void onResume(){super.onResume();if(surface!=null)surface.onResume();}
    @Override protected void onPause(){if(surface!=null)surface.onPause();super.onPause();}

    private static final class PreviewRenderer implements GLSurfaceView.Renderer {
        private static final String VS=
            "uniform mat4 m; attribute vec3 p; attribute vec3 c; varying vec3 v;"+
            "void main(){v=c;gl_Position=m*vec4(p,1.0);}";
        private static final String FS=
            "precision mediump float; varying vec3 v;"+
            "void main(){gl_FragColor=vec4(v,1.0);}";
        private final GtaDffMesh mesh;
        private final float[] projection=new float[16],camera=new float[16],rotation=new float[16];
        private final float[] vp=new float[16],mvp=new float[16];
        private FloatBuffer data;
        private int program,pos,color,matrix;
        volatile float yaw=20f,pitch=15f,lastX,lastY;
        PreviewRenderer(GtaDffMesh mesh){this.mesh=mesh;}
        synchronized void turn(float x,float y){
            yaw+=x*.33f;
            pitch=Math.max(-85f,Math.min(85f,pitch+y*.28f));
        }
        private static int shader(int type,String code){
            int result=GLES20.glCreateShader(type);
            GLES20.glShaderSource(result,code);
            GLES20.glCompileShader(result);
            int[] okay=new int[1];GLES20.glGetShaderiv(result,GLES20.GL_COMPILE_STATUS,okay,0);
            if(okay[0]==0)throw new IllegalStateException(GLES20.glGetShaderInfoLog(result));
            return result;
        }
        @Override public void onSurfaceCreated(GL10 unused,EGLConfig config){
            GLES20.glClearColor(.05f,.09f,.15f,1);
            GLES20.glEnable(GLES20.GL_DEPTH_TEST);
            GLES20.glDisable(GLES20.GL_CULL_FACE); // do not hide sections of heterogeneous GTA meshes
            int vs=shader(GLES20.GL_VERTEX_SHADER,VS),fs=shader(GLES20.GL_FRAGMENT_SHADER,FS);
            program=GLES20.glCreateProgram();
            GLES20.glAttachShader(program,vs);GLES20.glAttachShader(program,fs);
            GLES20.glLinkProgram(program);
            int[] linked=new int[1];GLES20.glGetProgramiv(program,GLES20.GL_LINK_STATUS,linked,0);
            if(linked[0]==0)throw new IllegalStateException(GLES20.glGetProgramInfoLog(program));
            GLES20.glDeleteShader(vs);GLES20.glDeleteShader(fs);
            pos=GLES20.glGetAttribLocation(program,"p");
            color=GLES20.glGetAttribLocation(program,"c");
            matrix=GLES20.glGetUniformLocation(program,"m");
            ByteBuffer bytes=ByteBuffer.allocateDirect(mesh.triangles.length*4)
                .order(ByteOrder.nativeOrder());
            data=bytes.asFloatBuffer();
            data.put(mesh.triangles);data.position(0);
        }
        @Override public void onSurfaceChanged(GL10 unused,int width,int height){
            GLES20.glViewport(0,0,width,height);
            Matrix.perspectiveM(projection,0,48f,(float)width/Math.max(1,height),.1f,80f);
        }
        @Override public void onDrawFrame(GL10 unused){
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT|GLES20.GL_DEPTH_BUFFER_BIT);
            float a,b;
            synchronized(this){a=yaw;b=pitch;}
            Matrix.setLookAtM(camera,0,0f,0.8f,7f,0f,0f,0f,0f,1f,0f);
            Matrix.setIdentityM(rotation,0);
            Matrix.rotateM(rotation,0,b,1f,0f,0f);
            Matrix.rotateM(rotation,0,a,0f,1f,0f);
            Matrix.multiplyMM(vp,0,projection,0,camera,0);
            Matrix.multiplyMM(mvp,0,vp,0,rotation,0);
            GLES20.glUseProgram(program);
            GLES20.glUniformMatrix4fv(matrix,1,false,mvp,0);
            data.position(0);
            GLES20.glVertexAttribPointer(pos,3,GLES20.GL_FLOAT,false,24,data);
            data.position(3);
            GLES20.glVertexAttribPointer(color,3,GLES20.GL_FLOAT,false,24,data);
            GLES20.glEnableVertexAttribArray(pos);
            GLES20.glEnableVertexAttribArray(color);
            GLES20.glDrawArrays(GLES20.GL_TRIANGLES,0,mesh.triangles.length/6);
            GLES20.glDisableVertexAttribArray(pos);
            GLES20.glDisableVertexAttribArray(color);
        }
    }
}
