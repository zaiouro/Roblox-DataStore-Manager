// ===== DRIFTING DARK CLOUDS =====
const canvas=document.getElementById('bg');
const ctx=canvas.getContext('2d');
let W,H,clouds=[],frame=0;
const CLOUD_TONES=[
  {r:96,g:110,b:152},{r:68,g:82,b:120},{r:118,g:132,b:172},{r:82,g:94,b:132}
];
function resize(){
  const dpr=Math.min(devicePixelRatio||1,1.5);
  const nw=Math.round(innerWidth*dpr),nh=Math.round(innerHeight*dpr);
  if(nw===W&&nh===H)return;
  const sx=W>0?nw/W:1,sy=H>0?nh/H:1;
  for(const c of clouds){
    c.x*=sx;c.y*=sy;
  }
  W=canvas.width=nw;H=canvas.height=nh;
  const want=Math.floor((W/dpr)*(H/dpr)/220000)+(innerWidth<700?1:3);
  while(clouds.length<want)clouds.push(makeCloud());
  if(clouds.length>want+6)clouds.length=want;
}
function makeCloud(){
  const baseR=70+Math.random()*110;
  const n=(innerWidth<700?4:7)+Math.floor(Math.random()*(innerWidth<700?3:5));
  const puffs=[];
  for(let i=0;i<n;i++){
    puffs.push({
      ox:(Math.random()-.5)*baseR*2,
      oy:(Math.random()-.5)*baseR*.6-baseR*.12,
      r:baseR*(.3+Math.random()*.7)
    });
  }
  const tone=CLOUD_TONES[Math.floor(Math.random()*CLOUD_TONES.length)];
  return {
    x:Math.random()*(W+baseR*2)-baseR,
    y:H*(.02+Math.random()*.6),
    s:.6+Math.random()*1.6,
    sp:.04+Math.random()*.18,
    o:.12+Math.random()*.08,
    bob:Math.random()*Math.PI*2,
    tone,puffs
  };
}
function init(){
  resize();
  const dpr=Math.min(devicePixelRatio||1,1.5);
  clouds=Array.from({length:Math.floor((W/dpr)*(H/dpr)/220000)+(innerWidth<700?1:3)},makeCloud);
}
function puff(x,y,r,tone,o,shade){
  const g=ctx.createRadialGradient(x,y,0,x,y,r);
  const rr=Math.max(0,tone.r+shade);
  const gg=Math.max(0,tone.g+shade);
  const bb=Math.max(0,tone.b+shade);
  g.addColorStop(0,`rgba(${rr},${gg},${bb},${o})`);
  g.addColorStop(.75,`rgba(${rr},${gg},${bb},${o*.55})`);
  g.addColorStop(1,`rgba(${rr},${gg},${bb},0)`);
  ctx.fillStyle=g;
  ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);ctx.fill();
}
function drawCloud(c){
  const cx=c.x,cw=c.s;
  const avgR=c.puffs.reduce((a,p)=>a+p.r,0)/c.puffs.length;
  puff(cx,c.y+16*cw,avgR*1.3*cw,c.tone,c.o*1.5,-34);
  c.puffs.forEach(p=>{
    puff(cx+p.ox*cw,c.y+p.oy*cw,p.r*cw,c.tone,c.o,0);
  });
  c.puffs.forEach(p=>{
    puff(cx+p.ox*cw-p.r*cw*.18,c.y+p.oy*cw-p.r*cw*.24,p.r*cw*.58,c.tone,c.o*.85,46);
  });
}
function tick(){
  frame++;
  ctx.clearRect(0,0,W,H);
  for(const c of clouds){
    c.x+=c.sp;
    c.y+=Math.sin(frame*.002+c.bob)*.02;
    if(c.x-c.s*160>W+60)c.x=-c.s*160;
    drawCloud(c);
  }
  requestAnimationFrame(tick);
}
addEventListener('resize',resize);
init();tick();

// ===== SCROLL-FOLLOWING GRADIENT =====
const bgGrad=document.querySelector('.bg-gradient');
function updateGradient(){
  const max=document.body.scrollHeight-innerHeight;
  const p=max>0?window.scrollY/max:0;
  bgGrad.style.backgroundPosition=`0% ${(p*100).toFixed(2)}%`;
}
addEventListener('scroll',updateGradient,{passive:true});
updateGradient();

// ===== MOBILE MENU =====
const menuBtn=document.getElementById('menu-btn'),mNav=document.querySelector('nav');
menuBtn.addEventListener('click',()=>{
  const open=mNav.classList.toggle('open');
  menuBtn.classList.toggle('open',open);
});
mNav.addEventListener('click',e=>{
  if(e.target.tagName==='A'){mNav.classList.remove('open');menuBtn.classList.remove('open');}
});

// ===== SELECTION & CONTEXT MENU LOCK =====
document.addEventListener('contextmenu',e=>e.preventDefault());
document.addEventListener('keydown',e=>{
  if(e.key==='F12'||(e.ctrlKey&&e.shiftKey&&['I','J','C'].includes(e.key.toUpperCase()))||(e.ctrlKey&&e.key.toLowerCase()==='u')){
    e.preventDefault();
  }
});

// ===== SMOOTH WHEEL SCROLLING =====
let smTarget=window.scrollY,smCurrent=window.scrollY,smActive=false,smWheel=false;
function smStep(){
  smCurrent+=(smTarget-smCurrent)*0.14;
  if(Math.abs(smTarget-smCurrent)<0.6){
    window.scrollTo({top:smTarget,behavior:'auto'});
    smActive=false;
    smWheel=false;
    return;
  }
  window.scrollTo({top:smCurrent,behavior:'auto'});
  requestAnimationFrame(smStep);
}
addEventListener('wheel',e=>{
  if(e.ctrlKey||e.metaKey)return;
  e.preventDefault();
  const max=document.documentElement.scrollHeight-innerHeight;
  smTarget=Math.max(0,Math.min(max,smTarget+e.deltaY));
  smWheel=true;
  if(!smActive){smActive=true;requestAnimationFrame(smStep);}
},{passive:false});
addEventListener('scroll',()=>{
  if(!smWheel&&!smActive){smTarget=window.scrollY;smCurrent=window.scrollY;}
},{passive:true});
