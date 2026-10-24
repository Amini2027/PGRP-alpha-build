package ir.paladinguard.gameclient;

/** Deterministic no-Android movement math, reusable for tests and future prediction. */
public final class WorldMath {
    private WorldMath() {}
    public static final class Pose {
        public float x;
        public float y;
        public float z;
        public float yaw;
        public float pitch;
        public Pose(float x, float y, float z) { this.x=x; this.y=y; this.z=z; }
    }

    public static float clamp(float value, float min, float max) {
        return Math.max(min,Math.min(max,value));
    }

    public static void turn(Pose pose, float dxPx, float dyPx, float sensitivity) {
        pose.yaw += dxPx * sensitivity;
        pose.pitch = clamp(pose.pitch - dyPx * sensitivity,-1.22f,1.22f);
        if (pose.yaw>Math.PI*2 || pose.yaw<-Math.PI*2) {
            pose.yaw = (float)Math.IEEEremainder(pose.yaw, Math.PI*2);
        }
    }

    public static void step(Pose pose, float strafe, float forward, float seconds, float speed) {
        seconds=clamp(seconds,0f,0.05f);
        float mag=(float)Math.sqrt(strafe*strafe+forward*forward);
        if(mag>1f){strafe/=mag;forward/=mag;}
        // Y-axis is up, yaw=0 looks along negative Z. Keep walking on the plane.
        float fX=(float)Math.sin(pose.yaw);
        float fZ=-(float)Math.cos(pose.yaw);
        float rX=(float)Math.cos(pose.yaw);
        float rZ=(float)Math.sin(pose.yaw);
        pose.x+=(fX*forward+rX*strafe)*seconds*speed;
        pose.z+=(fZ*forward+rZ*strafe)*seconds*speed;
        // Prevent the camera from escaping the generated prototype district.
        pose.x=clamp(pose.x,-169f,169f);
        pose.z=clamp(pose.z,-169f,169f);
    }
}
