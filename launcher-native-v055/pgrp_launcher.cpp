// PGRP native launcher 0.5.5 — Direct2D/DirectWrite, no CLR/WebView/runtime bundle.
// Win10+ x64. One HWND render target, bounded animation, WinSock query worker.
#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <windowsx.h>
#include <d2d1.h>
#include <d2d1helper.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <shlobj.h>
#include <commdlg.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <array>
#include <algorithm>
#include <cmath>
#include <atomic>
#include <thread>
#include <string>
#include <vector>
#include <memory>
#include <cwctype>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <cstdio>
#pragma comment(lib,"d2d1.lib")
#pragma comment(lib,"dwrite.lib")
#pragma comment(lib,"ole32.lib")
#pragma comment(lib,"shell32.lib")
#pragma comment(lib,"comdlg32.lib")
#pragma comment(lib,"ws2_32.lib")
#pragma comment(lib,"user32.lib")

using Microsoft::WRL::ComPtr;
constexpr UINT WM_PGRP_QUERY=WM_APP+55;
constexpr float NAV=212.0f, TOP=69.0f;
constexpr wchar_t SERVER[]=L"46.38.138.33";
constexpr unsigned short PORT=7777;

struct Node {float x,y,vx,vy;};
struct ServerResult {bool online=false;int players=0,maxPlayers=0,ping=0;};
enum class Page {Home,News,Settings,Help};
enum class Action {Home,News,Settings,Help,Play,Browse,Refresh,Save,LowSpec,Close,Minimize};
struct Hit {Action act;D2D1_RECT_F rect;};
static bool inside(D2D1_RECT_F r,float x,float y){return x>=r.left&&x<=r.right&&y>=r.top&&y<=r.bottom;}
static D2D1_RECT_F box(float x,float y,float w,float h){return D2D1::RectF(x,y,x+w,y+h);}
static D2D1_COLOR_F rgba(int r,int g,int b,float a=1.f){return D2D1::ColorF(r/255.f,g/255.f,b/255.f,a);}
constexpr UINT_PTR ANIM_TIMER=1, SERVER_TIMER=2;

struct App {
 HWND hwnd=nullptr, nickname=nullptr, gtaPath=nullptr;
 ComPtr<ID2D1Factory> factory;
 ComPtr<IDWriteFactory> write;
 ComPtr<ID2D1HwndRenderTarget> target;
 ComPtr<ID2D1SolidColorBrush> pen;
 ComPtr<IDWriteTextFormat> latin,englishTiny,persian,persianTitle,persianLarge;
 std::array<Node,44> nodes{};
 std::vector<Hit> hits;
 Page page=Page::Home;
 float W=1280,H=760,mx=-1,my=-1;
 bool lowSpec=true;
 int tick=0;
 std::wstring baseDir,ini,gameExe,playerName;
 std::wstring status=L"در حال بررسی",users=L"— / —",latency=L"—";
 std::thread worker;
 std::atomic<bool> querying{false};
 bool shuttingDown=false;

 static std::wstring getBase(){
  wchar_t path[MAX_PATH]{};
  if(SUCCEEDED(SHGetFolderPathW(nullptr,CSIDL_LOCAL_APPDATA,nullptr,0,path)))
   return std::wstring(path)+L"\\PaladinGuard\\Launcher";
  return L".";
 }
 static std::wstring readIni(std::wstring const& path,wchar_t const* key,wchar_t const* fallback){
  wchar_t b[2048]{};
  GetPrivateProfileStringW(L"PGRP",key,fallback,b,2048,path.c_str());
  return b;
 }
 void save(){
  SHCreateDirectoryExW(nullptr,baseDir.c_str(),nullptr);
  WritePrivateProfileStringW(L"PGRP",L"GameExe",gameExe.c_str(),ini.c_str());
  WritePrivateProfileStringW(L"PGRP",L"Nickname",playerName.c_str(),ini.c_str());
  WritePrivateProfileStringW(L"PGRP",L"LowSpec",lowSpec?L"1":L"0",ini.c_str());
 }
 static bool file(std::wstring const& path){
  DWORD a=GetFileAttributesW(path.c_str());return a!=INVALID_FILE_ATTRIBUTES && !(a&FILE_ATTRIBUTE_DIRECTORY);
 }
 static bool dir(std::wstring const& path){
  DWORD a=GetFileAttributesW(path.c_str());return a!=INVALID_FILE_ATTRIBUTES && !!(a&FILE_ATTRIBUTE_DIRECTORY);
 }
 static std::wstring parent(std::wstring const& f){auto p=f.find_last_of(L"\\/");return p==std::wstring::npos?L"":f.substr(0,p);}
 static bool valid(std::wstring const& f){
  if(f.empty()||!file(f))return false;
  auto p=parent(f);
  return _wcsicmp(f.substr(f.find_last_of(L"\\/")+1).c_str(),L"gta_sa.exe")==0 &&
   file(p+L"\\opensamp.exe")&&file(p+L"\\Client.Native.dll")&&
   dir(p+L"\\models")&&dir(p+L"\\data");
 }
 void findGame(){
  if(valid(gameExe))return;
  wchar_t user[MAX_PATH]{};
  if(FAILED(SHGetFolderPathW(nullptr,CSIDL_LOCAL_APPDATA,nullptr,0,user)))return;
  for(auto version:{L"0.5.5",L"0.5.4",L"0.5.3",L"0.5.2",L"0.5.1"}){
   std::wstring p=std::wstring(user)+L"\\PaladinGuard\\PGRP_Alpha_v"+version+
    L"\\GTA_San_Andreas\\gta_sa.exe";
   if(valid(p)){gameExe=p;break;}
  }
 }
 bool init(HINSTANCE h){
  HRESULT hr=D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,factory.GetAddressOf());
  if(FAILED(hr))return false;
  hr=DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,__uuidof(IDWriteFactory),
                        reinterpret_cast<IUnknown**>(write.GetAddressOf()));
  if(FAILED(hr))return false;
  auto fmt=[&](ComPtr<IDWriteTextFormat>& f,float size, DWRITE_FONT_WEIGHT weight,
               wchar_t const* locale){
   return write->CreateTextFormat(L"Segoe UI",nullptr,weight,
    DWRITE_FONT_STYLE_NORMAL,DWRITE_FONT_STRETCH_NORMAL,size,locale,&f);
  };
  if(FAILED(fmt(latin,28,DWRITE_FONT_WEIGHT_BOLD,L"en-US")) ||
     FAILED(fmt(englishTiny,13,DWRITE_FONT_WEIGHT_NORMAL,L"en-US")) ||
     FAILED(fmt(persian,18,DWRITE_FONT_WEIGHT_NORMAL,L"fa-IR")) ||
     FAILED(fmt(persianTitle,32,DWRITE_FONT_WEIGHT_BOLD,L"fa-IR")) ||
     FAILED(fmt(persianLarge,23,DWRITE_FONT_WEIGHT_BOLD,L"fa-IR")))return false;
  latin->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
  englishTiny->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
  persian->SetReadingDirection(DWRITE_READING_DIRECTION_RIGHT_TO_LEFT);
  persianTitle->SetReadingDirection(DWRITE_READING_DIRECTION_RIGHT_TO_LEFT);
  persianLarge->SetReadingDirection(DWRITE_READING_DIRECTION_RIGHT_TO_LEFT);
  for(auto* f:{persian.Get(),persianTitle.Get(),persianLarge.Get()})
   f->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
  baseDir=getBase();
  ini=baseDir+L"\\settings-native-v055.ini";
  gameExe=readIni(ini,L"GameExe",L"");
  playerName=readIni(ini,L"Nickname",L"");
  lowSpec=readIni(ini,L"LowSpec",L"1")!=L"0";
  findGame();
  unsigned seed=0x51A7u;
  auto rnd=[&seed](){seed=seed*1664525u+1013904223u;return (seed>>8)/16777216.f;};
  for(auto& n:nodes){n={0.01f+rnd()*0.98f,0.05f+rnd()*0.90f,
                        (rnd()-.5f)*.0009f,(rnd()-.5f)*.0009f};}
  WNDCLASSEXW wc={sizeof(wc)};
  wc.hInstance=h;wc.lpszClassName=L"PGRP_NATIVE_D2D_WINDOW_055";
  wc.hCursor=LoadCursor(nullptr,IDC_ARROW);
  wc.hIcon=LoadIcon(nullptr,IDI_APPLICATION);
  wc.lpfnWndProc=&App::proc;
  wc.hbrBackground=nullptr;
  if(!RegisterClassExW(&wc))return false;
  hwnd=CreateWindowExW(0,wc.lpszClassName,L"PALADIN GUARD | PGRP ROLEPLAY",
    WS_OVERLAPPEDWINDOW|WS_VISIBLE,CW_USEDEFAULT,CW_USEDEFAULT,1340,860,
    nullptr,nullptr,h,this);
  if(!hwnd)return false;
  CreateWindowExW(0,L"STATIC",L"",WS_CHILD,0,0,0,0,hwnd,nullptr,h,nullptr);
  nickname=CreateWindowExW(WS_EX_CLIENTEDGE,L"EDIT",playerName.c_str(),
    WS_CHILD|WS_TABSTOP|ES_AUTOHSCROLL,0,0,100,32,hwnd,(HMENU)101,h,nullptr);
  gtaPath=CreateWindowExW(WS_EX_CLIENTEDGE,L"EDIT",gameExe.c_str(),
    WS_CHILD|ES_READONLY|ES_AUTOHSCROLL,0,0,100,32,hwnd,(HMENU)102,h,nullptr);
  SendMessageW(nickname,EM_SETLIMITTEXT,24,0);
  ShowWindow(hwnd,SW_SHOW);
  SetTimer(hwnd,ANIM_TIMER,lowSpec?67:33,nullptr);
  SetTimer(hwnd,SERVER_TIMER,12000,nullptr);
  layout();
  query();
  return true;
 }
 bool renderReady(){
  if(target)return true;
  RECT r{};GetClientRect(hwnd,&r);
  HRESULT hr=factory->CreateHwndRenderTarget(
     D2D1::RenderTargetProperties(),
     D2D1::HwndRenderTargetProperties(hwnd,D2D1::SizeU(
       std::max(1L,r.right-r.left),std::max(1L,r.bottom-r.top))),
     target.GetAddressOf());
  if(FAILED(hr))return false;
  return SUCCEEDED(target->CreateSolidColorBrush(rgba(255,255,255),pen.GetAddressOf()));
 }
 void color(D2D1_COLOR_F c){pen->SetColor(c);}
 void fill(D2D1_RECT_F r,D2D1_COLOR_F c,float radius=0){
  color(c);
  if(radius>0)target->FillRoundedRectangle(D2D1::RoundedRect(r,radius,radius),pen.Get());
  else target->FillRectangle(r,pen.Get());
 }
 void stroke(D2D1_RECT_F r,D2D1_COLOR_F c,float rad=12){
  color(c);target->DrawRoundedRectangle(D2D1::RoundedRect(r,rad,rad),pen.Get(),1.0f);
 }
 void line(float x1,float y1,float x2,float y2,D2D1_COLOR_F c,float width=1.f){
  color(c);target->DrawLine(D2D1::Point2F(x1,y1),D2D1::Point2F(x2,y2),pen.Get(),width);
 }
 void txt(std::wstring const& s,D2D1_RECT_F r,IDWriteTextFormat* fmt,D2D1_COLOR_F c){
  color(c);
  target->DrawTextW(s.c_str(),(UINT32)s.size(),fmt,r,pen.Get(),
      D2D1_DRAW_TEXT_OPTIONS_CLIP);
 }
 void circle(float x,float y,float radius,D2D1_COLOR_F c){
  color(c);target->FillEllipse(D2D1::Ellipse(D2D1::Point2F(x,y),radius,radius),pen.Get());
 }
 void action(Action id,std::wstring const& title,D2D1_RECT_F r,bool strong=false){
  fill(r,strong?rgba(227,182,106):rgba(42,54,67),10);
  stroke(r,strong?rgba(238,194,120):rgba(82,104,116),10);
  txt(title,box(r.left+12,r.top+8,r.right-r.left-24,r.bottom-r.top-12),
    persian.Get(),strong?rgba(16,21,27):rgba(234,238,240));
  hits.push_back({id,r});
 }
 void graph(D2D1_RECT_F r,bool hero){
  // At most 44x44 cheap distance checks/frame, no particles or per-frame heap allocations.
  auto c=hero?rgba(227,179,95,.37f):rgba(65,168,174,.16f);
  auto d=hero?rgba(244,193,119,.82f):rgba(89,191,196,.36f);
  for(size_t i=0;i<nodes.size();++i){
   float x=r.left+nodes[i].x*(r.right-r.left);
   float y=r.top+nodes[i].y*(r.bottom-r.top);
   int links=0;
   for(size_t j=i+1;j<nodes.size()&&links<3;++j){
    float xx=r.left+nodes[j].x*(r.right-r.left);
    float yy=r.top+nodes[j].y*(r.bottom-r.top);
    float dx=x-xx,dy=y-yy;
    if(dx*dx+dy*dy<9500.f){line(x,y,xx,yy,c);++links;}
   }
   circle(x,y,hero?2.2f:1.6f,d);
  }
 }
 void header(){
  fill(box(0,0,W,H),rgba(14,19,27));
  graph(box(NAV+6,TOP,W-NAV-12,H-TOP),false);
  fill(box(0,0,NAV,H),rgba(15,21,30,.97f));
  fill(box(0,0,W,TOP),rgba(13,19,28,.97f));
  fill(box(0,0,W,3),rgba(228,182,102));
  txt(L"PALADIN GUARD",box(28,20,320,39),latin.Get(),rgba(234,182,94));
  txt(L"PGRP  /  VERSION 0.5.5",box(W-254,25,225,30),englishTiny.Get(),rgba(151,178,188));
  txt(L"P G R P",box(22,109,184,43),latin.Get(),rgba(236,184,100));
  txt(L"PALADIN GUARD",box(22,154,190,23),englishTiny.Get(),rgba(240,237,231));
  txt(L"ROLEPLAY / IRAN",box(22,186,185,28),englishTiny.Get(),rgba(162,185,195));
  txt(L"COMMAND CENTER",box(22,269,190,27),englishTiny.Get(),rgba(222,173,96));
  Action a[]={Action::Home,Action::News,Action::Settings,Action::Help};
  const wchar_t* names[]={L"داشبورد",L"اطلاعیه‌ها",L"تنظیمات",L"راهنمای اتصال"};
  for(int i=0;i<4;++i){
   auto r=box(15,315+i*61,180,48);
   bool sel=(page==Page::Home&&i==0)||(page==Page::News&&i==1)||
      (page==Page::Settings&&i==2)||(page==Page::Help&&i==3);
   fill(r,sel?rgba(89,67,42):rgba(34,45,57),8);
   if(sel)fill(box(15,325+i*61,3,26),rgba(233,183,101));
   txt(names[i],box(30,321+i*61,152,35),persian.Get(),sel?rgba(242,193,111):rgba(233,232,231));
   hits.push_back({a[i],r});
  }
  txt(L"ENGINE / OPEN.MP",box(20,H-75,190,27),englishTiny.Get(),rgba(167,187,195));
  txt(L"LOW-SPEC NATIVE MODE",box(20,H-48,193,27),englishTiny.Get(),rgba(218,174,105));
 }
 void home(){
  float x=NAV+24,aw=W-x-24,y=TOP+24;
  float heroH=std::min(322.f,std::max(270.f,H*.44f));
  auto hero=box(x,y,aw,heroH);
  fill(hero,rgba(23,31,42,.98f),18);stroke(hero,rgba(128,105,65,.6f),18);
  float left=std::min(600.f,aw*.56f);
  auto gr=box(x+left+6,y+13,aw-left-23,heroH-26);
  graph(gr,true);
  line(x+left,y+25,x+left,y+heroH-25,rgba(236,189,115,.45f));
  txt(L"PALADIN GUARD  /  ROLEPLAY",box(x+35,y+23,left-45,30),englishTiny.Get(),rgba(229,182,99));
  txt(L"به قلمرو پالادین خوش آمدی",box(x+28,y+80,left-28,76),persianTitle.Get(),rgba(246,241,233));
  txt(L"ماجراجویی خودت را در دنیایی اختصاصی آغاز کن",box(x+35,y+156,left-55,42),persian.Get(),rgba(171,193,204));
  action(Action::Play,L"▶  ورود به سرور",box(x+32,y+heroH-82,std::max(185.f,left*.48f),49),true);
  action(Action::Settings,L"تنظیمات بازی",box(x+47+std::max(185.f,left*.48f),y+heroH-82,
    std::max(128.f,left*.26f),49));
  float below=y+heroH+18;float cw=(aw-30.f)/3.f;
  const wchar_t* labels[]={L"وضعیت سرور",L"بازیکنان آنلاین",L"پینگ لحظه‌ای"};
  const std::wstring vals[]={status,users,latency};
  for(int i=0;i<3;++i){
   float xx=x+i*(cw+15);
   auto c=box(xx,below,cw,111);
   fill(c,rgba(26,34,45,.97f),13);stroke(c,rgba(61,80,96,.6f),13);
   txt(labels[i],box(xx+20,below+12,cw-40,32),persian.Get(),rgba(169,190,198));
   txt(vals[i],box(xx+20,below+49,cw-40,40),persianLarge.Get(),i?rgba(241,242,237):rgba(233,181,101));
  }
  float oy=below+128;
  if(H-oy<100)return;
  auto area=box(x,oy,aw,H-oy-22);
  fill(area,rgba(24,32,43,.97f),14);stroke(area,rgba(66,82,96,.6f),14);
  txt(L"نسخه کلاینت",box(x+22,oy+14,aw*.48f,32),persian.Get(),rgba(234,181,98));
  txt(valid(gameExe)?L"PGRP 0.5.5 • Native launcher":L"مسیر GTA هنوز تنظیم نشده است",
     box(x+23,oy+53,aw*.55f,33),persian.Get(),rgba(235,238,240));
  txt(L"46.38.138.33:7777  /  SA-MP",box(x+22,oy+92,aw*.60f,30),englishTiny.Get(),rgba(159,182,195));
  action(Action::Refresh,L"↻  تازه‌سازی وضعیت",box(x+aw-222,oy+38,195,48));
 }
 void secondary(){
  float x=NAV+32,w=W-x-32,y=TOP+30;
  if(page==Page::News){
   txt(L"اطلاعیه‌های سرور",box(x,y,w,65),persianTitle.Get(),rgba(240,236,230));
   auto c=box(x,y+95,w,305);fill(c,rgba(24,33,43,.95f),16);stroke(c,rgba(90,103,110,.62f),16);
   txt(L"اعلامیه‌ها",box(x+30,y+130,w-60,49),persianLarge.Get(),rgba(231,181,103));
   txt(L"اخبار زنده پس از اتصال به سرویس انتشار نمایش داده می‌شوند.",
       box(x+30,y+207,w-60,45),persian.Get(),rgba(240,239,231));
  }else if(page==Page::Help){
   txt(L"راهنمای ورود",box(x,y,w,65),persianTitle.Get(),rgba(241,239,231));
   const wchar_t* steps[]={
    L"۱. بازی GTA San Andreas را از ستاپ اختصاصی PGRP نصب کن.",
    L"۲. نام شخصیت را در تنظیمات وارد کن؛ مانند Ali_McClellan.",
    L"۳. ورود به سرور را بزن و احراز هویت را کامل کن.",
    L"۴. محل ورود و خروج توسط گیم‌مود سرور ذخیره می‌شود."};
   for(int i=0;i<4;++i){fill(box(x,y+100+i*85,w,68),rgba(25,35,47,.98f),10);
    txt(steps[i],box(x+22,y+112+i*85,w-44,43),persian.Get(),rgba(231,236,239));}
  }else{
   txt(L"تنظیمات بازی",box(x,y,w,65),persianTitle.Get(),rgba(241,238,230));
   fill(box(x,y+94,w,407),rgba(25,35,46,.98f),15);
   txt(L"مسیر فایل gta_sa.exe",box(x+25,y+114,w-50,42),persianLarge.Get(),rgba(231,183,101));
   action(Action::Browse,L"انتخاب مسیر GTA",box(x+w-220,y+169,185,42));
   txt(L"نام شخصیت — Name_Surname",box(x+25,y+229,w-50,44),persianLarge.Get(),rgba(230,182,101));
   action(Action::LowSpec,lowSpec?L"✓  حالت کم‌مصرف روشن":L"حالت کم‌مصرف خاموش",
     box(x+25,y+368,295,46));
   action(Action::Save,L"ذخیره تنظیمات",box(x+25,y+521,228,50),true);
  }
 }
 void render(){
  if(!renderReady())return;
  hits.clear();
  target->BeginDraw();
  header();
  if(page==Page::Home)home();else secondary();
  HRESULT hr=target->EndDraw();
  if(hr==D2DERR_RECREATE_TARGET){pen.Reset();target.Reset();}
 }
 void layout(){
  RECT r{};GetClientRect(hwnd,&r);W=float(r.right);H=float(r.bottom);
  bool show=page==Page::Settings;
  float x=NAV+32,y=TOP+30;
  SetWindowPos(gtaPath,nullptr,int(x+28),int(y+172),int(std::max(220.f,W-x-300)),35,
    SWP_NOZORDER|SWP_NOACTIVATE);
  SetWindowPos(nickname,nullptr,int(x+28),int(y+296),int(std::max(240.f,std::min(535.f,W-x-70))),36,
    SWP_NOZORDER|SWP_NOACTIVATE);
  ShowWindow(gtaPath,show?SW_SHOW:SW_HIDE);
  ShowWindow(nickname,show?SW_SHOW:SW_HIDE);
  if(target)target->Resize(D2D1::SizeU(UINT(W),UINT(H)));
  InvalidateRect(hwnd,nullptr,FALSE);
 }
 void animate(){
  float hx=NAV+24+std::min(600.f,(W-NAV-48)*.56f)+6;
  float hy=TOP+37;
  float gw=W-hx-42;
  float gh=std::min(322.f,std::max(270.f,H*.44f))-26;
  for(auto& n:nodes){
   float px=hx+n.x*gw,py=hy+n.y*gh;
   float dx=px-mx,dy=py-my;
   float d2=dx*dx+dy*dy;
   if(mx>=hx && mx<hx+gw && my>hy && my<hy+gh && d2<190.f*190.f && d2>1){
    float d=std::sqrt(d2),force=(190-d)*.0000012f;
    n.vx+=dx/d*force;n.vy+=dy/d*force;
   }
   n.vx=std::clamp(n.vx*.982f,-.0014f,.0014f);
   n.vy=std::clamp(n.vy*.982f,-.0014f,.0014f);
   n.x+=n.vx;n.y+=n.vy;
   if(n.x<.02f||n.x>.98f)n.vx=-n.vx;
   if(n.y<.08f||n.y>.95f)n.vy=-n.vy;
   n.x=std::clamp(n.x,.02f,.98f);n.y=std::clamp(n.y,.08f,.95f);
  }
  ++tick;InvalidateRect(hwnd,nullptr,FALSE);
 }
 void browse(){
  wchar_t out[MAX_PATH]{};
  OPENFILENAMEW ofn={sizeof(ofn)};
  ofn.hwndOwner=hwnd;ofn.lpstrFile=out;ofn.nMaxFile=MAX_PATH;
  ofn.lpstrFilter=L"GTA San Andreas (gta_sa.exe)\0gta_sa.exe\0\0";
  ofn.Flags=OFN_FILEMUSTEXIST|OFN_PATHMUSTEXIST;
  if(!GetOpenFileNameW(&ofn))return;
  if(!valid(out)){MessageBoxW(hwnd,L"فایل GTA باید در پوشه نصب‌شده PGRP کنار opensamp.exe و Client.Native.dll باشد.",
                               L"مسیر نامعتبر",MB_ICONWARNING);return;}
  gameExe=out;SetWindowTextW(gtaPath,gameExe.c_str());save();InvalidateRect(hwnd,nullptr,FALSE);
 }
 void play(){
  wchar_t nick[50]{};GetWindowTextW(nickname,nick,50);playerName=nick;
  auto i=playerName.find(L'_');
  bool ok=i!=std::wstring::npos && i>0 && i+1<playerName.size() && playerName.size()<=24;
  for(auto c:playerName)if(!((c>=L'A'&&c<=L'Z')||(c>=L'a'&&c<=L'z')||
                              (c>=L'0'&&c<=L'9')||c==L'_'))ok=false;
  if(!ok){page=Page::Settings;layout();
    MessageBoxW(hwnd,L"نام شخصیت باید به شکل Name_Surname و حداکثر ۲۴ کاراکتر باشد.",
      L"PGRP Nickname",MB_ICONWARNING);return;}
  if(!valid(gameExe)){page=Page::Settings;layout();
    MessageBoxW(hwnd,L"ابتدا مسیر GTA در پوشه نصب‌شده PGRP را مشخص کن.",L"PGRP",MB_ICONWARNING);return;}
  save();
  std::wstring root=parent(gameExe),exe=root+L"\\opensamp.exe";
  // Scoped environment hand-off: restore previous environment after CreateProcess.
  wchar_t old[80]{};DWORD n=GetEnvironmentVariableW(L"PGRP_AUTOCONNECT_NICK",old,80);
  SetEnvironmentVariableW(L"PGRP_AUTOCONNECT_NICK",playerName.c_str());
  STARTUPINFOW si={sizeof(si)};PROCESS_INFORMATION pi{};
  BOOL started=CreateProcessW(exe.c_str(),nullptr,nullptr,nullptr,FALSE,0,nullptr,
                              root.c_str(),&si,&pi);
  if(n>0&&n<80)SetEnvironmentVariableW(L"PGRP_AUTOCONNECT_NICK",old);
  else SetEnvironmentVariableW(L"PGRP_AUTOCONNECT_NICK",nullptr);
  if(!started){MessageBoxW(hwnd,L"بازی اجرا نشد؛ فایل‌ها یا مجوز اجرای opensamp.exe را بررسی کن.",
                                L"PGRP Launch Error",MB_ICONERROR);return;}
  CloseHandle(pi.hThread);CloseHandle(pi.hProcess);
  DestroyWindow(hwnd); // Give RAM/GPU back to GTA after launching.
 }
 void click(int x,int y){
  for(auto const& h:hits)if(inside(h.rect,float(x),float(y))){
   switch(h.act){
    case Action::Home:page=Page::Home;break;
    case Action::News:page=Page::News;break;
    case Action::Settings:page=Page::Settings;break;
    case Action::Help:page=Page::Help;break;
    case Action::Browse:browse();break;
    case Action::Play:play();return;
    case Action::Refresh:query();break;
    case Action::LowSpec:lowSpec=!lowSpec;KillTimer(hwnd,ANIM_TIMER);
       SetTimer(hwnd,ANIM_TIMER,lowSpec?67:33,nullptr);save();break;
    case Action::Save:save();MessageBoxW(hwnd,L"تنظیمات ذخیره شد.",L"PGRP",MB_OK);break;
    default:break;
   }
   layout();return;
  }
  if(x>NAV&&y>TOP){
   // Click effect: recycle four existing nodes, never grow the vector.
   for(int i=0;i<4;++i){
    auto& n=nodes[(tick+i*11)%nodes.size()];
    n.x=std::clamp((x-(NAV+24))/(std::max(1.f,W-NAV-48))+(i-2)*.022f,.03f,.97f);
    n.y=std::clamp((y-TOP)/(std::max(1.f,H-TOP))+(i-2)*.018f,.07f,.95f);
   }
  }
 }
 void query(){
  if(querying.exchange(true))return;
  if(worker.joinable())worker.join();
  HWND wh=hwnd;auto* a=this;
  worker=std::thread([wh,a](){
   auto* result=new ServerResult();
   SOCKET sock=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);
   if(sock!=INVALID_SOCKET){
    sockaddr_in addr={};addr.sin_family=AF_INET;addr.sin_port=htons(PORT);
    InetPtonW(AF_INET,SERVER,&addr.sin_addr);
    unsigned char q[11]={'S','A','M','P',46,38,138,33,0x61,0x1e,'i'};
    q[8]=BYTE(PORT&0xFF);q[9]=BYTE(PORT>>8);
    auto begin=GetTickCount64();
    if(sendto(sock,reinterpret_cast<char*>(q),11,0,
              reinterpret_cast<sockaddr*>(&addr),sizeof(addr))==11){
     fd_set r;FD_ZERO(&r);FD_SET(sock,&r);timeval t={1,200000};
     if(select(0,&r,nullptr,nullptr,&t)>0){
      unsigned char b[256]{};int len=recv(sock,reinterpret_cast<char*>(b),sizeof(b),0);
      if(len>=16 && memcmp(b,"SAMP",4)==0 && b[10]=='i'){
       result->online=true;
       result->players=int(b[12]|b[13]<<8);
       result->maxPlayers=int(b[14]|b[15]<<8);
       result->ping=int(GetTickCount64()-begin);
      }
     }
    }
    closesocket(sock);
   }
   if(!PostMessageW(wh,WM_PGRP_QUERY,0,reinterpret_cast<LPARAM>(result)))delete result;
   a->querying.store(false);
  });
 }
 LRESULT on(UINT msg,WPARAM wp,LPARAM lp){
  switch(msg){
   case WM_CREATE:return 0;
   case WM_SIZE:layout();return 0;
   case WM_PAINT:{
    PAINTSTRUCT ps{};BeginPaint(hwnd,&ps);render();EndPaint(hwnd,&ps);return 0;
   }
   case WM_ERASEBKGND:return 1;
   case WM_TIMER: if(wp==ANIM_TIMER)animate();else if(wp==SERVER_TIMER)query();return 0;
   case WM_MOUSEMOVE:mx=float(GET_X_LPARAM(lp));my=float(GET_Y_LPARAM(lp));return 0;
   case WM_LBUTTONUP:click(GET_X_LPARAM(lp),GET_Y_LPARAM(lp));return 0;
   case WM_COMMAND:if(LOWORD(wp)==101&&HIWORD(wp)==EN_CHANGE){
     wchar_t b[50]{};GetWindowTextW(nickname,b,50);playerName=b;save();}return 0;
   case WM_PGRP_QUERY:{
    std::unique_ptr<ServerResult> r(reinterpret_cast<ServerResult*>(lp));
    if(r->online){
     status=L"آنلاین";users=std::to_wstring(r->players)+L" / "+std::to_wstring(r->maxPlayers);
     latency=std::to_wstring(r->ping)+L" ms";
    } else {status=L"پاسخ نامشخص";users=L"— / —";latency=L"—";}
    InvalidateRect(hwnd,nullptr,FALSE);return 0;
   }
   case WM_DESTROY:
    shuttingDown=true;KillTimer(hwnd,ANIM_TIMER);KillTimer(hwnd,SERVER_TIMER);
    if(worker.joinable())worker.join();save();PostQuitMessage(0);return 0;
  }
  return DefWindowProcW(hwnd,msg,wp,lp);
 }
 static LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){
  App* a=reinterpret_cast<App*>(GetWindowLongPtrW(h,GWLP_USERDATA));
  if(m==WM_NCCREATE){
   auto cs=reinterpret_cast<CREATESTRUCTW*>(l);
   a=reinterpret_cast<App*>(cs->lpCreateParams);
   a->hwnd=h;SetWindowLongPtrW(h,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(a));
  }
  return a?a->on(m,w,l):DefWindowProcW(h,m,w,l);
 }
};
int WINAPI wWinMain(HINSTANCE h,HINSTANCE,LPWSTR,int){
 WSADATA data{};
 if(WSAStartup(MAKEWORD(2,2),&data)!=0)return 1;
 auto app=std::make_unique<App>();
 if(!app->init(h)){MessageBoxW(nullptr,L"Direct2D/DirectWrite initialization failed.",L"PGRP",MB_ICONERROR);WSACleanup();return 2;}
 MSG m{};while(GetMessageW(&m,nullptr,0,0)>0){TranslateMessage(&m);DispatchMessageW(&m);}
 app.reset();WSACleanup();return 0;
}
