#pragma once
// PGRP FreeCam v0.5.17 — dependency-free controller for GTA SA (Z-up).
// This file provides camera mathematics and state ONLY. The game adapter must
// consume WM_INPUT relative deltas ONCE per rendered frame, own the camera
// during FreeCam, and restore GTA camera/input on exit. No process hooks here.
#include <cmath>
#include <algorithm>

namespace pgrp {
struct Vec3 {
    double x = 0.0, y = 0.0, z = 0.0;
    Vec3() = default;
    Vec3(double ax, double ay, double az) : x(ax), y(ay), z(az) {}
    Vec3 operator+(Vec3 b) const { return {x+b.x,y+b.y,z+b.z}; }
    Vec3 operator-(Vec3 b) const { return {x-b.x,y-b.y,z-b.z}; }
    Vec3 operator*(double s) const { return {x*s,y*s,z*s}; }
    Vec3& operator+=(Vec3 b) { x+=b.x; y+=b.y; z+=b.z; return *this; }
};
inline double dot(Vec3 a, Vec3 b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
inline Vec3 cross(Vec3 a, Vec3 b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
inline double norm(Vec3 a) { return std::sqrt(dot(a,a)); }
inline Vec3 unit(Vec3 a, Vec3 fallback = {0,1,0}) {
    const double n=norm(a);
    return (std::isfinite(n)&&n>1e-12) ? a*(1.0/n) : fallback;
}
inline bool finite(Vec3 a) { return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z); }
struct Quat {
    double w = 1, x = 0, y = 0, z = 0;
    Quat() = default;
    Quat(double aw,double ax,double ay,double az) : w(aw),x(ax),y(ay),z(az) {}
    Quat operator*(Quat q) const {
        return { w*q.w-x*q.x-y*q.y-z*q.z,
                 w*q.x+x*q.w+y*q.z-z*q.y,
                 w*q.y-x*q.z+y*q.w+z*q.x,
                 w*q.z+x*q.y-y*q.x+z*q.w };
    }
    static Quat axis_angle(Vec3 axis,double a) {
        axis=unit(axis,{0,0,1});
        const double s=std::sin(a*0.5);
        return {std::cos(a*0.5), axis.x*s,axis.y*s,axis.z*s};
    }
    Quat normalized() const {
        const double n=std::sqrt(w*w+x*x+y*y+z*z);
        return (std::isfinite(n)&&n>1e-12) ? Quat{w/n,x/n,y/n,z/n} : Quat{};
    }
    Vec3 rotate(Vec3 v) const {
        // Assumes normalized quaternion. Avoid q * v * conjugate allocations.
        const Vec3 u{x,y,z};
        const Vec3 t=cross(u,v)*2.0;
        return v+t*w+cross(u,t);
    }
};
struct Controls {
    double mouse_dx = 0.0;        // relative RAW mouse counts accumulated per frame
    double mouse_dy = 0.0;
    double forward = 0.0;         // W +1, S -1 (NOT inverted)
    double right = 0.0;           // D +1, A -1
    double rise = 0.0;            // SPACE +1, CTRL -1 (world Z)
    bool fast = false;            // SHIFT
};
struct Pose { Vec3 position; Vec3 forward; Vec3 right; Vec3 up; };
class FreeCamController {
public:
    bool active() const { return active_; }
    void begin(Vec3 position, Quat orientation) {
        active_=true; focused_=false; position_=finite(position)?position:Vec3{};
        orientation_=orientation.normalized(); velocity_={};
    }
    void end() { active_=false; focused_=false; velocity_={}; }
    void focus(bool value) {
        if (!value || !focused_) velocity_={};  // don't apply stale movement on focus return
        focused_=value;
    }
    bool focused() const { return focused_; }
    void configure(double radiansPerMouseCount,double normalSpeed,double fastSpeed,double inertiaRate=20.0) {
        if(std::isfinite(radiansPerMouseCount) && radiansPerMouseCount>0 && radiansPerMouseCount<0.1) sensitivity_=radiansPerMouseCount;
        if(std::isfinite(normalSpeed) && normalSpeed>0 && normalSpeed<1000) speed_=normalSpeed;
        if(std::isfinite(fastSpeed) && fastSpeed>=normalSpeed && fastSpeed<5000) boost_=fastSpeed;
        if(std::isfinite(inertiaRate) && inertiaRate>0 && inertiaRate<1000) inertia_=inertiaRate;
    }
    void tick(const Controls& raw,double dt) {
        if (!active_ || !focused_ || !std::isfinite(dt) || dt<=0) return;
        dt=std::min(dt,0.05); // hitch guard (no giant teleports)
        Controls c=raw;
        // Raw mouse is per-frame displacement. Do NOT divide by dt or call SetCursorPos.
        if (!std::isfinite(c.mouse_dx)||!std::isfinite(c.mouse_dy)) return;
        const double dx=std::clamp(c.mouse_dx,-2000.0,2000.0);
        const double dy=std::clamp(c.mouse_dy,-2000.0,2000.0);
        // Local yaw/pitch quaternion: no Euler +/-90-degree singularity or flip.
        // Full vertical loops are continuous; an upside-down horizon halfway through
        // a full 360-degree loop is normal physical 6-DOF camera behavior.
        const Quat localYaw=Quat::axis_angle({0,0,1},-dx*sensitivity_);
        const Quat localPitch=Quat::axis_angle({1,0,0},-dy*sensitivity_);
        orientation_=(orientation_*localYaw*localPitch).normalized();
        auto limited=[](double n) {return std::isfinite(n)?std::clamp(n,-1.0,1.0):0.0;};
        const double f=limited(c.forward), r=limited(c.right), z=limited(c.rise);
        Vec3 wish=orientation_.rotate({0,1,0})*f + orientation_.rotate({1,0,0})*r + Vec3{0,0,1}*z;
        const double n=norm(wish); if(n>1) wish=wish*(1/n); // diagonal normalization
        const Vec3 target=wish*(c.fast?boost_:speed_);
        // Frame-rate-independent velocity damping. 20/s settles quickly without jitter.
        const double alpha=1.0-std::exp(-inertia_*dt);
        velocity_+= (target-velocity_)*alpha;
        position_+= velocity_*dt;
        if (!finite(position_)) { active_=false; velocity_={}; }
    }
    Pose pose() const {
        return {position_, unit(orientation_.rotate({0,1,0})),
                unit(orientation_.rotate({1,0,0}),{1,0,0}),
                unit(orientation_.rotate({0,0,1}),{0,0,1})};
    }
    // Initialize safely from an existing GTA camera basis; forward/up in WORLD space.
    static Quat orientation_from_basis(Vec3 forward,Vec3 approximateUp={0,0,1}) {
        forward=unit(forward);
        Vec3 r=cross(forward,approximateUp);
        if (norm(r)<1e-8) r=cross(forward,{0,1,0});
        if (norm(r)<1e-8) r=cross(forward,{1,0,0});
        r=unit(r,{1,0,0});
        const Vec3 u=unit(cross(r,forward),{0,0,1});
        const double m00=r.x,m01=forward.x,m02=u.x;
        const double m10=r.y,m11=forward.y,m12=u.y;
        const double m20=r.z,m21=forward.z,m22=u.z;
        const double trace=m00+m11+m22;
        Quat q;
        if(trace>0){double s=std::sqrt(trace+1.0)*2; q={s*.25,(m21-m12)/s,(m02-m20)/s,(m10-m01)/s};}
        else if(m00>m11 && m00>m22){double s=std::sqrt(1+m00-m11-m22)*2; q={(m21-m12)/s,s*.25,(m01+m10)/s,(m02+m20)/s};}
        else if(m11>m22){double s=std::sqrt(1+m11-m00-m22)*2; q={(m02-m20)/s,(m01+m10)/s,s*.25,(m12+m21)/s};}
        else {double s=std::sqrt(1+m22-m00-m11)*2; q={(m10-m01)/s,(m02+m20)/s,(m12+m21)/s,s*.25};}
        return q.normalized();
    }
private:
    bool active_=false,focused_=false;
    Vec3 position_{},velocity_{};
    Quat orientation_{};
    double sensitivity_=0.0025,speed_=10.0,boost_=28.0,inertia_=20.0;
};
} // namespace pgrp
