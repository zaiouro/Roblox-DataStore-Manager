const transition=document.getElementById('transition');
const BAR_MS=1600;
const viaNav=sessionStorage.getItem('hd_nav');
if(viaNav){
  sessionStorage.removeItem('hd_nav');
  transition.classList.remove('cover');
  transition.classList.add('reveal');
  setTimeout(()=>transition.classList.remove('reveal'),600);
}else{
  const dataWait=window.__pageReady?Promise.race([window.__pageReady,new Promise(r=>setTimeout(r,4000))]):Promise.resolve();
  const loadWait=Promise.race([
    new Promise(r=>document.readyState==='complete'?r():addEventListener('load',r,{once:true})),
    new Promise(r=>setTimeout(r,2500))
  ]);
  Promise.all([loadWait,dataWait]).then(()=>{
    transition.classList.remove('cover');
    transition.classList.add('active');
    setTimeout(()=>transition.classList.remove('active'),2200);
  });
}
document.querySelectorAll('a[href]').forEach(a=>{
  const href=a.getAttribute('href');
  if(!href||href.startsWith('http'))return;
  const curPage=location.pathname.split('/').pop()||'index.html';
  if(href.split('#')[0]===curPage){
    a.addEventListener('click',e=>e.preventDefault());
    return;
  }
  a.addEventListener('click',e=>{
    e.preventDefault();
    sessionStorage.setItem('hd_nav','1');
    transition.classList.add('active');
    setTimeout(()=>location.href=href,BAR_MS);
  });
});
