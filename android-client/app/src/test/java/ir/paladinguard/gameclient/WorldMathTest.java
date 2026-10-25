package ir.paladinguard.gameclient;
import org.junit.Test;
import static org.junit.Assert.*;

public class WorldMathTest {
    @Test public void forwardYawZeroWalksNegativeZ(){
        WorldMath.Pose pose=new WorldMath.Pose(0,1,12);
        WorldMath.step(pose,0,1,.05f,5f);
        assertEquals(0f,pose.x,.0001f);
        assertEquals(11.75f,pose.z,.0001f);
    }
    @Test public void strafeRightYawZeroMovesPositiveX(){
        WorldMath.Pose pose=new WorldMath.Pose(0,1,0);
        WorldMath.step(pose,1,0,.05f,5f);
        assertEquals(.25f,pose.x,.0001f);
        assertEquals(0f,pose.z,.0001f);
    }
    @Test public void touchLookRightTurnsTowardsRight(){
        WorldMath.Pose pose=new WorldMath.Pose(0,1,0);
        WorldMath.turn(pose,100,0,.004f);
        assertTrue(pose.yaw>0f);
    }
    @Test public void pitchClampedNeverFlipsWorld(){
        WorldMath.Pose pose=new WorldMath.Pose(0,1,0);
        WorldMath.turn(pose,0,-20000,.004f);
        assertEquals(1.22f,pose.pitch,.0001f);
        WorldMath.turn(pose,0,20000,.004f);
        assertEquals(-1.22f,pose.pitch,.0001f);
    }
    @Test public void diagonalSpeedNormalized(){
        WorldMath.Pose pose=new WorldMath.Pose(0,1,0);
        WorldMath.step(pose,1,1,.05f,5f);
        assertEquals(.25f,Math.hypot(pose.x,pose.z),.0001f);
    }
    @Test public void frameSpikesCannotTeleportPlayer(){
        WorldMath.Pose pose=new WorldMath.Pose(0,1,0);
        WorldMath.step(pose,0,1,999f,5f);
        assertEquals(-.25f,pose.z,.0001f);
    }
    @Test public void stayInsidePrototypeWorld(){
        WorldMath.Pose pose=new WorldMath.Pose(169,1,169);
        WorldMath.step(pose,1,-1,.05f,5f);
        assertTrue(pose.x<=169f && pose.z<=169f);
    }
}
