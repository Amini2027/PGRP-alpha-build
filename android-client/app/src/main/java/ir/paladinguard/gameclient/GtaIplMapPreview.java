package ir.paladinguard.gameclient;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import java.util.Locale;

/** Diagnostic 2D positions from original text IPL, never a claimed 3D GTA scene. */
public final class GtaIplMapPreview extends View {
    private final GtaMapPlacementIndex.Result data;
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private final ScaleGestureDetector scale;
    private float zoom,centerX=GtaMapPlacementIndex.CENTER_X,centerY=GtaMapPlacementIndex.CENTER_Y;
    private float lastX,lastY;
    public GtaIplMapPreview(Context context,GtaMapPlacementIndex.Result map) {
        super(context);
        data=map;
        zoom=context.getResources().getDisplayMetrics().density*.15f;
        scale=new ScaleGestureDetector(context,new ScaleGestureDetector.SimpleOnScaleGestureListener(){
            @Override public boolean onScale(ScaleGestureDetector detector){
                zoom=Math.max(.025f,Math.min(6f,zoom*detector.getScaleFactor()));
                invalidate();return true;
            }
        });
    }
    @Override protected void onDraw(Canvas canvas){
        int w=getWidth(),h=getHeight();
        canvas.drawColor(0xFF101D2A);
        float ox=w/2f,oy=h/2f;
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(1f);
        paint.setColor(0x224FC5E0);
        for(int x=-35;x<=35;x++){
            float at=ox+(x*100f+GtaMapPlacementIndex.CENTER_X-centerX)*zoom;
            if(at>=0&&at<=w)canvas.drawLine(at,0,at,h,paint);
        }
        for(int y=-35;y<=35;y++){
            float at=oy-(y*100f+GtaMapPlacementIndex.CENTER_Y-centerY)*zoom;
            if(at>=0&&at<=h)canvas.drawLine(0,at,w,at,paint);
        }
        paint.setStyle(Paint.Style.FILL);
        int visible=0;
        for(GtaMapPlacementIndex.Instance obj:data.visibleSamples){
            float x=ox+(obj.x-centerX)*zoom;
            float y=oy-(obj.y-centerY)*zoom;
            if(x<-6||x>w+6||y<-6||y>h+6)continue;
            String name=obj.modelName.toLowerCase(Locale.ROOT);
            paint.setColor(name.contains("road")||name.contains("street")?0xFF58CCEC:0xFFE0BD78);
            canvas.drawCircle(x,y,Math.max(1.4f,Math.min(3.6f,zoom*7f)),paint);
            visible++;
        }
        paint.setColor(0xFFF3F7FA);
        paint.setTextSize(getResources().getDisplayMetrics().scaledDensity*12f);
        canvas.drawText("GTA SA: text-IPL locations (NOT actual models)",12,25,paint);
        canvas.drawText("Markers: "+visible+" / instances: "+data.instances,12,46,paint);
        canvas.drawText("Los Santos  |  drag or pinch to inspect",12,h-18,paint);
        paint.setColor(0xFFFFA65A);
        paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(2);
        float x=ox+(GtaMapPlacementIndex.CENTER_X-centerX)*zoom;
        float y=oy-(GtaMapPlacementIndex.CENTER_Y-centerY)*zoom;
        canvas.drawLine(x-7,y,x+7,y,paint);
        canvas.drawLine(x,y-7,x,y+7,paint);
        paint.setStyle(Paint.Style.FILL);
    }
    @Override public boolean onTouchEvent(MotionEvent event){
        scale.onTouchEvent(event);
        switch(event.getActionMasked()){
            case MotionEvent.ACTION_DOWN:
                lastX=event.getX();lastY=event.getY();return true;
            case MotionEvent.ACTION_MOVE:
                if(event.getPointerCount()==1&&!scale.isInProgress()){
                    float nextX=event.getX(),nextY=event.getY();
                    centerX=Math.max(-3500f,Math.min(3500f,centerX-(nextX-lastX)/zoom));
                    centerY=Math.max(-3500f,Math.min(3500f,centerY+(nextY-lastY)/zoom));
                    lastX=nextX;lastY=nextY;invalidate();
                }
                return true;
            case MotionEvent.ACTION_POINTER_UP:
                if(event.getPointerCount()>1){lastX=event.getX(0);lastY=event.getY(0);}return true;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:return true;
            default:return true;
        }
    }
}