// PGRP native launcher 0.5.5 — Direct2D/DirectWrite, no CLR/WebView/runtime bundle.
// Win10+ x64. One HWND render target, bounded animation, WinSock query worker.
#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <windowsx.h>
#include <d2d1.h>
#include <d2d1helper.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <shlobj.h>
#include <commdlg.h>
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
 ComPtr<IDWriteTextFormat> latin,latinValue,englishTiny,persian,persianTitle,persianLarge;
 std::array<Node,72> nodes{};
 std::array<int,90> pingHistory{};
 size_t pingHead=0,pingCount=0;
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
  // One-folder install: gta_sa.exe lives right next to PGRPLauncher.exe.
  // Favor that verified local copy even if a previous launcher saved an older
  // path in the persistent settings.
  wchar_t myself[32768]{};
  if(GetModuleFileNameW(nullptr,myself,32768)>0){
   std::wstring here=parent(myself)+L"\\gta_sa.exe";
   if(valid(here)){gameExe=here;return;}
  }
  if(valid(gameExe))return;
  wchar_t user[MAX_PATH]{};
  if(FAILED(SHGetFolderPathW(nullptr,CSIDL_LOCAL_APPDATA,nullptr,0,user)))return;
  for(auto version:{L"0.5.14",L"0.5.7",L"0.5.6",L"0.5.5",L"0.5.4",L"0.5.3",L"0.5.2",L"0.5.1"}){
   std::wstring root=std::wstring(user)+L"\\PaladinGuard\\PGRP_Alpha_v"+version;
   for(auto candidate:{root+L"\\gta_sa.exe",root+L"\\GTA_San_Andreas\\gta_sa.exe"}){
    if(valid(candidate)){gameExe=candidate;return;}
   }
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
     FAILED(fmt(latinValue,23,DWRITE_FONT_WEIGHT_BOLD,L"en-US")) ||
     FAILED(fmt(englishTiny,13,DWRITE_FONT_WEIGHT_NORMAL,L"en-US")) ||
     FAILED(fmt(persian,18,DWRITE_FONT_WEIGHT_NORMAL,L"fa-IR")) ||
     FAILED(fmt(persianTitle,32,DWRITE_FONT_WEIGHT_BOLD,L"fa-IR")) ||
     FAILED(fmt(persianLarge,23,DWRITE_FONT_WEIGHT_BOLD,L"fa-IR")))return false;
  latin->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
  latinValue->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
  englishTiny->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
  persian->SetReadingDirection(DWRITE_READING_DIRECTION_RIGHT_TO_LEFT);
  persianTitle->SetReadingDirection(DWRITE_READING_DIRECTION_RIGHT_TO_LEFT);
  persianLarge->SetReadingDirection(DWRITE_READING_DIRECTION_RIGHT_TO_LEFT);
  for(auto* f:{persian.Get(),persianTitle.Get(),persianLarge.Get()})
   f->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
  baseDir=getBase();
  ini=baseDir+L"\\settings-native-v055.ini"; // reuse prior user nickname and path
  gameExe=readIni(ini,L"GameExe",L"");
  playerName=readIni(ini,L"Nickname",L"");
  lowSpec=readIni(ini,L"LowSpec",L"1")!=L"0";
  findGame();
  unsigned seed=0x51A7u;
  auto rnd=[&seed](){seed=seed*1664525u+1013904223u;return (seed>>8)/16777216.f;};
  pingHistory.fill(-1);
  for(auto& n:nodes){n={0.018f+rnd()*0.964f,0.02f+rnd()*0.96f,
                        (rnd()-.5f)*.0009f,(rnd()-.5f)*.0009f};}
  WNDCLASSEXW wc={sizeof(wc)};
  wc.hInstance=h;wc.lpszClassName=L"PGRP_NATIVE_D2D_WINDOW_055";
  wc.hCursor=LoadCursor(nullptr,IDC_ARROW);
  wc.hIcon=LoadIcon(nullptr,IDI_APPLICATION);
  wc.lpfnWndProc=&App::proc;
  wc.hbrBackground=nullptr;
  if(!RegisterClassExW(&wc))return false;
  hwnd=CreateWindowExW(0,wc.lpszClassName,L"PALADIN GUARD ROLEPLAY",
    WS_OVERLAPPEDWINDOW|WS_VISIBLE,CW_USEDEFAULT,CW_USEDEFAULT,1340,860,
    nullptr,nullptr,h,this);
  if(!hwnd)return false;
  CreateWindowExW(0,L"STATIC",L"",WS_CHILD,0,0,0,0,hwnd,nullptr,h,nullptr);
  nickname=CreateWindowExW(WS_EX_CLIENTEDGE,L"EDIT",playerName.c_str(),
    WS_CHILD|WS_TABSTOP|ES_AUTOHSCROLL,0,0,100,32,hwnd,(HMENU)101,h,nullptr);
  gtaPath=CreateWindowExW(WS_EX_CLIENTEDGE,L"EDIT",gameExe.c_str(),
    WS_CHILD|ES_READONLY|ES_AUTOHSCROLL,0,0,100,32,hwnd,(HMENU)102,h,nullptr);
  SendMessageW(nickname,EM_SETLIMITTEXT,24,0);
  ShowWindow(hwnd,SW_SHOWMAXIMIZED);
  SetTimer(hwnd,ANIM_TIMER,lowSpec?67:33,nullptr);
  SetTimer(hwnd,SERVER_TIMER,1500,nullptr);
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
  // Numbers and endpoint labels must remain LTR; Persian uses full shaping.
  bool hasPersian=false;
  for(auto ch:s) if(ch>=0x0600 && ch<=0x06ff){hasPersian=true;break;}
  if(!hasPersian && fmt==persianLarge.Get())fmt=latinValue.Get();
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
 // Single world-space mesh: drawn once, not restarted in each panel.
 // Every node connects to its nearest earlier neighbor. This forms one
 // continuous connected graph with at most one extra local edge per node.
 void graph(){
  const D2D1_COLOR_F colors[]={
    rgba(230,180,93,.32f),rgba(70,166,229,.32f),
    rgba(220,72,79,.32f),rgba(229,239,253,.29f)};
  for(size_t i=0;i<nodes.size();++i){
   float x=nodes[i].x*W,y=nodes[i].y*H;
   if(i>0){
    size_t n1=0,n2=0;float d1=1e15f,d2=1e15f;
    for(size_t j=0;j<i;++j){
     float dx=x-nodes[j].x*W,dy=y-nodes[j].y*H;
     float d=dx*dx+dy*dy;
     if(d<d1){d2=d1;n2=n1;d1=d;n1=j;}
     else if(d<d2){d2=d;n2=j;}
    }
    line(x,y,nodes[n1].x*W,nodes[n1].y*H,colors[i%4],.95f);
    if(i>3&&d2<37000.f)
      line(x,y,nodes[n2].x*W,nodes[n2].y*H,colors[(i+2)%4],.7f);
   }
   auto c=colors[i%4];c.a=.7f;circle(x,y,2.35f,c);
  }
 }
 void pingSample(int value){
  pingHistory[pingHead]=value;
  pingHead=(pingHead+1)%pingHistory.size();
  if(pingCount<pingHistory.size())++pingCount;
 }
 void drawPing(D2D1_RECT_F r){
  float w=r.right-r.left,h=r.bottom-r.top;
  if(w<40.f||h<30.f)return;
  float maximum=80.f;
  for(size_t i=0;i<pingCount;++i){
   int value=pingHistory[(pingHead+pingHistory.size()-pingCount+i)%pingHistory.size()];
   if(value>=0) maximum=std::max(maximum,float(value)*1.3f);
  }
  maximum=std::min(maximum,3000.f);
  for(int g=0;g<4;++g){
   float y=r.top+h*float(g)/3.f;
   line(r.left,y,r.right,y,rgba(190,200,214,.13f),.7f);
  }
  bool hasPrevious=false;float px=0,py=0;
  for(size_t i=0;i<pingCount;++i){
   int value=pingHistory[(pingHead+pingHistory.size()-pingCount+i)%pingHistory.size()];
   float x=r.left+(pingCount>1?float(i)/float(pingCount-1):1.f)*w;
   if(value<0){hasPrevious=false;continue;}
   float y=r.bottom-std::min(float(value)/maximum,1.f)*h;
   if(hasPrevious)line(px,py,x,y,rgba(94,212,228,.98f),1.85f);
   if(i+1==pingCount)circle(x,y,3.35f,rgba(242,186,100,.95f));
   px=x;py=y;hasPrevious=true;
  }
 }
 void header(){
  fill(box(0,0,W,H),rgba(14,19,27));
  graph();
  fill(box(0,0,NAV,H),rgba(15,21,30,.78f));
  fill(box(0,0,W,TOP),rgba(13,19,28,.82f));
  fill(box(0,0,W,3),rgba(228,182,102));
  txt(L"PALADIN GUARD ROLEPLAY",box(28,20,550,39),latin.Get(),rgba(234,182,94));
  txt(L"CLIENT  /  VERSION 0.5.14",box(W-254,25,225,30),englishTiny.Get(),rgba(151,178,188));
  txt(L"ROLEPLAY",box(22,112,188,43),latin.Get(),rgba(236,184,100));
  txt(L"IRAN  /  ONLINE WORLD",box(22,172,185,30),englishTiny.Get(),rgba(162,185,195));
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
  txt(L"ENTER YOUR WORLD",box(20,H-65,190,29),englishTiny.Get(),rgba(218,174,105));
 }
 void home(){
  const float x=NAV+24.f, aw=std::max(520.f,W-x-24.f), y=TOP+21.f;
  // Three meaningful layers rather than six empty technical cards:
  // hero -> real-time numbers -> one full-width ping timeline.
  const float heroH=std::min(288.f,std::max(226.f,(H-TOP)*.355f));
  const auto hero=box(x,y,aw,heroH);
  fill(hero,rgba(23,31,42,.77f),18);
  stroke(hero,rgba(128,105,65,.60f),18);
  const float left=std::min(750.f,aw*.64f);
  line(x+left,y+22,x+left,y+heroH-22,rgba(236,189,115,.32f));
  txt(L"YOUR WORLD  /  YOUR STORY",box(x+32,y+16,left-40,30),
      englishTiny.Get(),rgba(229,182,99));
  txt(L"به قلمرو پالادین خوش آمدی",box(x+28,y+55,left-40,52),
      persianLarge.Get(),rgba(246,241,233));
  txt(L"ماجراجویی خودت را در دنیایی اختصاصی آغاز کن",
      box(x+30,y+109,left-44,34),persian.Get(),rgba(179,195,205));
  const float playW=std::max(194.f,left*.49f);
  action(Action::Play,L"▶  ورود به سرور",box(x+30,y+heroH-72,playW,47),true);
  action(Action::Settings,L"تنظیمات بازی",
      box(x+44+playW,y+heroH-72,std::max(145.f,left*.28f),47));

  const float topStatus=y+heroH+15.f;
  const float cardsGap=13.f,cw=(aw-cardsGap*2.f)/3.f;
  const wchar_t* labels[]={L"وضعیت سرور",L"بازیکنان آنلاین",L"پینگ لحظه‌ای"};
  const std::wstring vals[]={status,users,latency};
  for(int i=0;i<3;++i){
    const float cx=x+i*(cw+cardsGap);
    auto card=box(cx,topStatus,cw,101.f);
    fill(card,rgba(24,33,44,.76f),13);
    stroke(card,rgba(65,84,99,.64f),13);
    txt(labels[i],box(cx+18,topStatus+11,cw-36,29),
        persian.Get(),rgba(182,197,207));
    txt(vals[i],box(cx+19,topStatus+43,cw-38,44),
        persianLarge.Get(),i==0?rgba(231,184,107):rgba(235,240,244));
  }

  const float graphTop=topStatus+115.f;
  const float graphH=std::max(124.f,H-graphTop-23.f);
  const auto card=box(x,graphTop,aw,graphH);
  fill(card,rgba(20,29,40,.72f),13);
  stroke(card,rgba(63,87,106,.60f),13);
  txt(L"نمودار زنده پینگ",box(x+24,graphTop+12,aw*.60f,32),
      persian.Get(),rgba(238,185,101));
  txt(L"آخرین اندازه‌گیری‌ها",box(x+24,graphTop+42,aw*.60f,27),
      persian.Get(),rgba(160,180,197));
  const float chartLeft=x+24.f, chartTop=graphTop+77.f;
  drawPing(box(chartLeft,chartTop,aw-48.f,std::max(43.f,graphH-97.f)));
 }
 void secondary(){
  float x=NAV+32,w=W-x-32,y=TOP+30;
  if(page==Page::News){
   txt(L"اطلاعیه‌های سرور",box(x,y,w,65),persianTitle.Get(),rgba(240,236,230));
   auto c=box(x,y+95,w,std::max(305.f,H-y-140));fill(c,rgba(24,33,43,.74f),16);stroke(c,rgba(90,103,110,.62f),16);
   txt(L"اعلامیه‌ها",box(x+30,y+130,w-60,49),persianLarge.Get(),rgba(231,181,103));
   txt(L"اخبار زنده پس از اتصال به سرویس انتشار نمایش داده می‌شوند.",
       box(x+30,y+207,w-60,45),persian.Get(),rgba(240,239,231));
  }else if(page==Page::Help){
   txt(L"راهنمای ورود",box(x,y,w,65),persianTitle.Get(),rgba(241,239,231));
   const wchar_t* steps[]={
    L"۱. بازی GTA San Andreas را با ستاپ اختصاصی Paladin Guard نصب کن.",
    L"۲. نام شخصیت را در تنظیمات وارد کن؛ مانند Ali_McClellan.",
    L"۳. ورود به سرور را بزن و احراز هویت را کامل کن.",
    L"۴. محل ورود و خروج توسط گیم‌مود سرور ذخیره می‌شود."};
   for(int i=0;i<4;++i){fill(box(x,y+100+i*85,w,68),rgba(25,35,47,.72f),10);
    txt(steps[i],box(x+22,y+112+i*85,w-44,43),persian.Get(),rgba(231,236,239));}
  }else{
   txt(L"تنظیمات بازی",box(x,y,w,65),persianTitle.Get(),rgba(241,238,230));
   fill(box(x,y+94,w,std::max(500.f,H-y-126)),rgba(25,35,46,.75f),15);
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
  if(!hwnd || !nickname || !gtaPath)return;
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
  // Exactly one graph frame; mouse affects nodes in the SAME full-screen
  // coordinate space on Home, Settings, Help and News.
  for(auto& n:nodes){
   float x=n.x*W,y=n.y*H;
   float dx=x-mx,dy=y-my,dist=dx*dx+dy*dy;
   if(mx>=0&&my>=0&&dist>12.f&&dist<205.f*205.f){
    float inv=1.f/std::sqrt(dist);
    float force=(205.f-1.f/inv)*.0000010f;
    n.vx+=dx*inv*force;
    n.vy+=dy*inv*force;
   }
   // Stable low-amplitude drift never damps to zero. Mouse repulsion adds
   // temporary velocity, then nodes return gradually to autonomous motion.
   const size_t k=static_cast<size_t>(&n-&nodes[0]);
   const float desiredX=std::sin(float(k)*1.713f+float(tick)*.0009f)*.000270f;
   const float desiredY=std::cos(float(k)*1.297f+float(tick)*.00075f)*.000225f;
   n.vx=std::clamp(n.vx*.963f+desiredX*.037f,-.00115f,.00115f);
   n.vy=std::clamp(n.vy*.963f+desiredY*.037f,-.00115f,.00115f);
   n.x+=n.vx;n.y+=n.vy;
   if(n.x<.015f||n.x>.985f)n.vx=-n.vx;
   if(n.y<.03f||n.y>.975f)n.vy=-n.vy;
   n.x=std::clamp(n.x,.015f,.985f);
   n.y=std::clamp(n.y,.03f,.975f);
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
  if(!valid(out)){MessageBoxW(hwnd,L"فایل GTA باید کنار opensamp.exe و Client.Native.dll در پوشه نصب باشد.",
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
      L"Paladin Guard Roleplay",MB_ICONWARNING);return;}
  if(!valid(gameExe)){page=Page::Settings;layout();
    MessageBoxW(hwnd,L"ابتدا مسیر GTA در پوشه نصب‌شده بازی را مشخص کن.",L"Paladin Guard Roleplay",MB_ICONWARNING);return;}
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
                                L"Paladin Guard Launch Error",MB_ICONERROR);return;}
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
    case Action::Save:save();MessageBoxW(hwnd,L"تنظیمات ذخیره شد.",L"Paladin Guard",MB_OK);break;
    default:break;
   }
   layout();return;
  }
  if(x>NAV&&y>TOP){
   // Click effect: recycle four existing nodes, never grow the vector.
   for(int i=0;i<4;++i){
    auto& n=nodes[(tick+i*11)%nodes.size()];
    n.x=std::clamp(float(x)/std::max(1.f,W)+(i-2)*.022f,.02f,.98f);
    n.y=std::clamp(float(y)/std::max(1.f,H)+(i-2)*.018f,.035f,.97f);
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
     pingSample(r->ping);
    } else {status=L"پاسخ نامشخص";users=L"— / —";latency=L"—";pingSample(-1);}
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
