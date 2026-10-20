#pragma once
// PGRP 0.5.21: GTA SA uses world Z as up. Shared by render and movement.
#include <cmath>
namespace pgrpfc_math {
struct Vec3 { float x,y,z; };
struct Basis { Vec3 right,up,forward; };
inline Basis BuildBasis(float yaw,float pitch) noexcept {
    const float cy=std::cos(yaw),sy=std::sin(yaw);
    const float cp=std::cos(pitch),sp=std::sin(pitch);
    // Right cross Up == Forward. No Euler matrix extraction/gimbal singularity.
    return {{-sy,cy,0.f},{-cy*sp,-sy*sp,cp},{cy*cp,sy*cp,sp}};
}
inline Vec3 FlightDirection(float yaw,float pitch,float forwardAxis,
                            float strafeAxis,float altitudeAxis) noexcept {
    const auto b=BuildBasis(yaw,pitch);
    const float x=forwardAxis*b.forward.x+strafeAxis*b.right.x;
    const float y=forwardAxis*b.forward.y+strafeAxis*b.right.y;
    const float z=forwardAxis*b.forward.z+altitudeAxis;
    const float length=std::sqrt(x*x+y*y+z*z);
    return length>0.0001f ? Vec3{x/length,y/length,z/length} : Vec3{0.f,0.f,0.f};
}
}
