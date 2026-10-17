#include "../include/pgrp_freecam_controller.h"
#include <cassert>
#include <cmath>
#include <iostream>
using namespace pgrp;
static bool near(double a,double b,double eps=1e-5){return std::abs(a-b)<eps;}
static bool vnear(Vec3 a,Vec3 b,double e=1e-5){return norm(a-b)<e;}
int main(){
    auto base=FreeCamController::orientation_from_basis({0,1,0});
    FreeCamController cam;
    cam.begin({10,20,30},base);
    cam.tick(Controls{100,100,1},1./60.); // no mouse input until foreground
    assert(vnear(cam.pose().position,{10,20,30}));
    cam.focus(true);
    assert(vnear(cam.pose().forward,{0,1,0}));
    // W should move forward, S should move backwards.
    for(int i=0;i<60;i++){ Controls c; c.forward=1; cam.tick(c,1./60.); }
    assert(cam.pose().position.y>20);
    const double forwardPosition=cam.pose().position.y;
    for(int i=0;i<120;i++){Controls c; c.forward=-1;cam.tick(c,1./60.);}
    assert(cam.pose().position.y<forwardPosition);
    const Pose saved=cam.pose();
    cam.focus(false);
    for(int i=0;i<20;i++){Controls c; c.mouse_dx=500; c.forward=1; cam.tick(c,1./60.);}
    assert(vnear(cam.pose().position,saved.position));
    assert(vnear(cam.pose().forward,saved.forward));
    cam.focus(true);
    assert(vnear(cam.pose().forward,saved.forward));
    // 360-degree vertical pitch is continuous, including crossing both poles.
    cam.begin({0,0,0},base);cam.focus(true);
    cam.configure(3.14159265358979323846/180,10,28);
    Vec3 last=cam.pose().forward;
    const Vec3 first=last;
    for(int i=0;i<360;i++){
        Controls c;c.mouse_dy=-1;cam.tick(c,1./60.);
        const auto p=cam.pose();
        assert(dot(last,p.forward)>0.9998); // no discrete world flip between frames
        assert(near(dot(p.forward,p.right),0,1e-8));
        assert(near(dot(p.forward,p.up),0,1e-8));
        assert(near(dot(p.right,p.up),0,1e-8));
        last=p.forward;
    }
    assert(vnear(cam.pose().forward,first,1e-8));
    // Near vertical, no NaNs or degenerate basis.
    cam.begin({1,2,3},FreeCamController::orientation_from_basis({0,0,1}));
    cam.focus(true);
    for(int i=0;i<2000;i++){Controls c;c.mouse_dx=3;c.mouse_dy=2;cam.tick(c,1./144.);}
    assert(finite(cam.pose().forward)&&finite(cam.pose().up));
    assert(near(norm(cam.pose().forward),1));
    // Reject NaN mouse input rather than destroying the camera matrix.
    const Pose prev=cam.pose();Controls bad;bad.mouse_dx=std::nan("");cam.tick(bad,1./60.);
    assert(vnear(prev.forward,cam.pose().forward));
    cam.end(); assert(!cam.active());
    std::cout<<"PGRP FreeCam controller: ALL TESTS PASSED\n";
}
