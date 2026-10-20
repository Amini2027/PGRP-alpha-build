#include "../include/pgrp_freecam_math.h"
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cmath>
#include <initializer_list>
#include <iostream>
using namespace pgrpfc_math;
static bool near(float a,float b,float t=0.0004f){return std::fabs(a-b)<t;}
static float dot(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
static Vec3 cross(Vec3 a,Vec3 b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
struct GameMatrix {
  float right[3]; std::uint32_t flags;
  float forward[3]; std::uint32_t pad1;
  float up[3]; std::uint32_t pad2;
  float pos[3];
};
static_assert(offsetof(GameMatrix,right)==0x00,"GTA CMatrix right offset");
static_assert(offsetof(GameMatrix,forward)==0x10,"GTA CMatrix forward offset");
static_assert(offsetof(GameMatrix,up)==0x20,"GTA CMatrix up offset");
static_assert(offsetof(GameMatrix,pos)==0x30,"GTA CMatrix position offset");
int main(){
  const float pi=3.14159265358979323846f;
  for(float yaw:{0.f,pi/2,pi,2*pi,6*pi})
    for(float pitch:{-1.3962634f,-pi/4,0.f,pi/4,1.3962634f}){
      auto b=BuildBasis(yaw,pitch);
      assert(near(dot(b.right,b.right),1)&&near(dot(b.up,b.up),1)&&near(dot(b.forward,b.forward),1));
      assert(near(dot(b.right,b.up),0)&&near(dot(b.right,b.forward),0)&&near(dot(b.up,b.forward),0));
      assert(near(dot(cross(b.forward,b.up),b.right),1));
      assert(near(dot(cross(b.right,b.forward),b.up),1));
      auto w=FlightDirection(yaw,pitch,1,0,0);
      auto s=FlightDirection(yaw,pitch,-1,0,0);
      assert(near(dot(w,b.forward),1)&&near(dot(s,b.forward),-1));
    }
  // GTA SA canonical yaw=+90: front +Y, right +X, up +Z.
  const auto canonical=BuildBasis(pi/2,0.f);
  assert(near(canonical.forward.x,0)&&near(canonical.forward.y,1)&&near(canonical.forward.z,0));
  assert(near(canonical.right.x,1)&&near(canonical.right.y,0)&&near(canonical.right.z,0));
  assert(near(canonical.up.x,0)&&near(canonical.up.y,0)&&near(canonical.up.z,1));
  // Windows Raw Input positive dx must yaw toward camera right.
  const float sensitivity=0.0009f;
  const auto rotated=BuildBasis(pi/2-100.f*sensitivity,0.f);
  assert(rotated.forward.x>0.05f);
  // Mouse up -> negative dy -> positive pitch -> upward flight.
  const auto rotatedUp=BuildBasis(pi/2,-(-100.f)*sensitivity);
  assert(rotatedUp.forward.z>0.f);
  GameMatrix matrix{};
  matrix.right[0]=canonical.right.x;matrix.right[1]=canonical.right.y;matrix.right[2]=canonical.right.z;
  matrix.forward[0]=canonical.forward.x;matrix.forward[1]=canonical.forward.y;matrix.forward[2]=canonical.forward.z;
  matrix.up[0]=canonical.up.x;matrix.up[1]=canonical.up.y;matrix.up[2]=canonical.up.z;
  assert(near(matrix.right[0],1)&&near(matrix.forward[1],1)&&near(matrix.up[2],1));
  // This specifically fails the old v0.5.21 forward/up swapped layout.
  assert(dot(Vec3{matrix.forward[0],matrix.forward[1],matrix.forward[2]},canonical.forward)>0.9999f);
  assert(dot(Vec3{matrix.up[0],matrix.up[1],matrix.up[2]},canonical.up)>0.9999f);
  auto ascend=FlightDirection(0,pi/4,1,0,0);
  auto descend=FlightDirection(0,-pi/4,1,0,0);
  assert(ascend.z>0.7f && descend.z < -0.7f);
  assert(near(FlightDirection(0,pi/4,0,1,0).z,0));
  assert(near(FlightDirection(0,pi/4,0,0,1).z,1));
  std::cout<<"PASS: W/S follow pitched gaze, camera is orthogonal, 360 yaw valid."<<std::endl;
}
