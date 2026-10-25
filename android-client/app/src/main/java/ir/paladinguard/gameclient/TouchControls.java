package ir.paladinguard.gameclient;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.view.View;

/** Multi-touch joystick + free-look, owned by PGRP without any other game client. */
public final class TouchControls extends View {
    private final WorldRenderer game;
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private int movePointer=-1;
    private int lookPointer=-1;
    private float moveBaseX,moveBaseY,moveX,moveY;
    private float lookX,lookY;
    private final float density;
    private float radius;
    private float padX,padY;

    public TouchControls(Context context,WorldRenderer game){
        super(context);
        this.game=game;
        density=getResources().getDisplayMetrics().density;
        setLayerType(View.LAYER_TYPE_SOFTWARE,null);
        setContentDescription("Left virtual joystick and right free-look area");
    }

    @Override protected void onSizeChanged(int w,int h,int oldW,int oldH){
        super.onSizeChanged(w,h,oldW,oldH);
        radius=Math.min(75*density,h*.20f);
        padX=Math.max(115*density,w*.14f);
        padY=h-Math.max(94*density,h*.22f);
        moveBaseX=padX;
        moveBaseY=padY;
        moveX=moveBaseX;
        moveY=moveBaseY;
    }

    @Override protected void onDraw(Canvas canvas){
        super.onDraw(canvas);
        final float w=getWidth(),h=getHeight();
        paint.setColor(0x4428384E);
        paint.setStyle(Paint.Style.FILL);
        canvas.drawCircle(moveBaseX,moveBaseY,radius+8*density,paint);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(2*density);
        paint.setColor(0xCCEBBC68);
        canvas.drawCircle(moveBaseX,moveBaseY,radius,paint);
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(0xBB59C9EA);
        canvas.drawCircle(moveX,moveY,25*density,paint);

        paint.setColor(0xCCF2F4F7);
        paint.setTextSize(11*density);
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setFakeBoldText(true);
        canvas.drawText("MOVE",moveBaseX,moveBaseY-radius-18*density,paint);
        canvas.drawText("LOOK",w*.79f,h-32*density,paint);
        paint.setColor(0x66F2F4F7);
        paint.setStrokeWidth(1.2f*density);
        float cx=w*.81f, cy=h*.57f;
        canvas.drawLine(cx-13*density,cy,cx+13*density,cy,paint);
        canvas.drawLine(cx,cy-13*density,cx,cy+13*density,paint);
    }

    @Override public boolean onTouchEvent(MotionEvent event){
        int action=event.getActionMasked();
        int changeIndex=event.getActionIndex();
        if(action==MotionEvent.ACTION_DOWN||action==MotionEvent.ACTION_POINTER_DOWN){
            float x=event.getX(changeIndex),y=event.getY(changeIndex);
            int id=event.getPointerId(changeIndex);
            if(x<getWidth()*.44f && movePointer<0){
                movePointer=id;
                moveBaseX=padX;moveBaseY=padY;
                changeMove(x,y);
            }else if(lookPointer<0){
                lookPointer=id;lookX=x;lookY=y;
            }
        }else if(action==MotionEvent.ACTION_MOVE){
            int moveIndex=event.findPointerIndex(movePointer);
            if(moveIndex>=0)changeMove(event.getX(moveIndex),event.getY(moveIndex));
            int lookIndex=event.findPointerIndex(lookPointer);
            if(lookIndex>=0){
                float newX=event.getX(lookIndex),newY=event.getY(lookIndex);
                float dx=newX-lookX,dy=newY-lookY;
                if(Math.abs(dx)<150*density && Math.abs(dy)<150*density){
                    game.turn(dx/density,dy/density);
                }
                lookX=newX;lookY=newY;
            }
        }else if(action==MotionEvent.ACTION_UP || action==MotionEvent.ACTION_POINTER_UP){
            int id=event.getPointerId(changeIndex);
            if(id==movePointer){
                movePointer=-1;
                moveX=moveBaseX;moveY=moveBaseY;
                game.setMovement(0,0);
            }
            if(id==lookPointer)lookPointer=-1;
        }else if(action==MotionEvent.ACTION_CANCEL){
            movePointer=-1;lookPointer=-1;
            moveX=moveBaseX;moveY=moveBaseY;
            game.setMovement(0,0);
        }
        invalidate();
        return true;
    }

    private void changeMove(float x,float y){
        float dx=x-moveBaseX,dy=y-moveBaseY;
        float length=(float)Math.hypot(dx,dy);
        if(length>radius){dx*=radius/length;dy*=radius/length;}
        moveX=moveBaseX+dx;moveY=moveBaseY+dy;
        float axisX=dx/radius;
        float axisY=-dy/radius;
        if(Math.abs(axisX)<.07f)axisX=0f;
        if(Math.abs(axisY)<.07f)axisY=0f;
        game.setMovement(axisX,axisY);
    }
}
