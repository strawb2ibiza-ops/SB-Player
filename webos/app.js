(()=>{"use strict";
const $=id=>document.getElementById(id);let auth=null,view="live",items=[],categories=[],activeCat="all";
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
function base(){return auth.server.replace(/\/$/,"")}
function api(action,extra=""){return base()+"/player_api.php?username="+encodeURIComponent(auth.username)+"&password="+encodeURIComponent(auth.password)+(action?"&action="+action:"")+extra}
async function get(url){const r=await fetch(url);if(!r.ok)throw Error("HTTP "+r.status);return r.json()}
function save(){localStorage.setItem("sb.webos.auth",JSON.stringify(auth))}
function focusables(){return [...document.querySelectorAll("button:not([disabled]),input,.card,.cat")].filter(x=>x.offsetParent!==null)}
function focusFirst(){setTimeout(()=>focusables()[0]?.focus(),30)}
function moveFocus(key){
 const all=focusables(),cur=document.activeElement;if(!all.length)return;
 if(!all.includes(cur)){all[0].focus();return}
 const a=cur.getBoundingClientRect(),cx=a.left+a.width/2,cy=a.top+a.height/2;
 let best=null,score=Infinity;
 for(const el of all){if(el===cur)continue;const r=el.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2,dx=x-cx,dy=y-cy;
  if(key===37&&dx>=-4||key===39&&dx<=4||key===38&&dy>=-4||key===40&&dy<=4)continue;
  const primary=(key===37||key===39)?Math.abs(dx):Math.abs(dy),secondary=(key===37||key===39)?Math.abs(dy):Math.abs(dx),s=primary+secondary*2.2;
  if(s<score){score=s;best=el}}
 if(best){best.focus();best.scrollIntoView({block:"nearest",inline:"nearest"})}
}
async function signin(){const server=$("server").value.trim(),username=$("username").value.trim(),password=$("password").value;if(!server||!username||!password)return fail("Enter your server, username and password.");auth={server:/^https?:\/\//i.test(server)?server:"http://"+server,username,password};$("signin").disabled=true;$("status").textContent="Connecting…";fail("");try{const data=await get(api(""));if(!data.user_info||String(data.user_info.auth)!=="1")throw Error("Login rejected");save();showHome();await loadView("live")}catch(e){fail("Could not sign in: "+e.message);auth=null}$("signin").disabled=false;$("status").textContent=""}
function fail(s){$("error").textContent=s}
function showHome(){$("login").classList.add("hidden");$("home").classList.remove("hidden")}
async function loadView(v){view=v;activeCat="all";$("heading").textContent=v==="live"?"Live TV":v==="movies"?"Movies":"Series";document.querySelectorAll(".nav[data-view]").forEach(b=>b.classList.toggle("active",b.dataset.view===v));$("grid").innerHTML="<p>Loading…</p>";try{const ca=v==="live"?"get_live_categories":v==="movies"?"get_vod_categories":"get_series_categories";const ia=v==="live"?"get_live_streams":v==="movies"?"get_vod_streams":"get_series";[categories,items]=await Promise.all([get(api(ca)),get(api(ia))]);renderCats();render();focusFirst()}catch(e){$("grid").innerHTML="<p>Unable to load: "+esc(e.message)+"</p>"}}
function renderCats(){$("categories").innerHTML='<button class="cat focusable active" data-cat="all">All</button>'+categories.map(c=>'<button class="cat focusable" data-cat="'+esc(c.category_id)+'">'+esc(c.category_name)+'</button>').join("")}
function render(){const q=$("search").value.trim().toLowerCase();const f=items.filter(x=>(activeCat==="all"||String(x.category_id)===activeCat)&&String(x.name??x.title??"").toLowerCase().includes(q));$("grid").innerHTML=f.slice(0,1200).map(x=>{const name=x.name??x.title??"Untitled",img=x.stream_icon??x.cover??"";return '<button class="card focusable" data-i="'+items.indexOf(x)+'">'+(img?'<img src="'+esc(img)+'" onerror="this.style.display=\'none\'">':"")+'<strong>'+esc(name)+'</strong><small>'+esc(view==="live"?"Live":view==="movies"?"Movie":"Series")+'</small></button>'}).join("")||"<p>No results.</p>"}
function play(x){if(view==="series")return loadSeries(x);const ext=view==="live"?"ts":(x.container_extension||"mp4"),url=base()+"/"+(view==="live"?"live":"movie")+"/"+encodeURIComponent(auth.username)+"/"+encodeURIComponent(auth.password)+"/"+x.stream_id+"."+ext;openVideo(url,x.name??x.title)}
async function loadSeries(x){$("grid").innerHTML="<p>Loading episodes…</p>";try{const d=await get(api("get_series_info","&series_id="+encodeURIComponent(x.series_id))),eps=Object.values(d.episodes||{}).flat();$("grid").innerHTML=eps.map((e,i)=>'<button class="card focusable" data-episode="'+i+'"><strong>'+esc(e.title||("Episode "+e.episode_num))+'</strong><small>S'+esc(e.season||"")+" E"+esc(e.episode_num||"")+"</small></button>").join("");$("grid").onclick=ev=>{const b=ev.target.closest("[data-episode]");if(!b)return;const e=eps[+b.dataset.episode],ext=e.container_extension||"mp4";openVideo(base()+"/series/"+encodeURIComponent(auth.username)+"/"+encodeURIComponent(auth.password)+"/"+e.id+"."+ext,e.title)};focusFirst()}catch(e){$("grid").innerHTML="<p>Unable to load series.</p>"}}
function openVideo(url,title){$("player").classList.remove("hidden");$("playingTitle").textContent=title||"";$("video").src=url;$("video").play().catch(()=>{});$("back").focus()}
function closeVideo(){$("video").pause();$("video").removeAttribute("src");$("video").load();$("player").classList.add("hidden");focusFirst()}
function activate(el){if(!el)return;if(el.tagName==="INPUT"){el.focus();return}el.click()}
document.addEventListener("click",e=>{const nav=e.target.closest("[data-view]");if(nav)return loadView(nav.dataset.view);const cat=e.target.closest("[data-cat]");if(cat){activeCat=cat.dataset.cat;document.querySelectorAll(".cat").forEach(x=>x.classList.toggle("active",x===cat));render();return}const card=e.target.closest("[data-i]");if(card)return play(items[+card.dataset.i])});
document.addEventListener("keydown",e=>{const k=e.keyCode||e.which;if([37,38,39,40].includes(k)){e.preventDefault();moveFocus(k);return}if(k===13){e.preventDefault();activate(document.activeElement);return}if(k===461||e.key==="Backspace"||e.key==="Escape"){if(!$("player").classList.contains("hidden")){e.preventDefault();closeVideo();return}if(view!=="live"){e.preventDefault();loadView("live")}}});
$("signin").addEventListener("click",signin);$("login").addEventListener("submit",e=>{e.preventDefault();signin()});$("search").oninput=render;$("back").onclick=closeVideo;$("logout").onclick=()=>{localStorage.removeItem("sb.webos.auth");location.reload()};
try{const s=JSON.parse(localStorage.getItem("sb.webos.auth")||"null");if(s){auth=s;showHome();loadView("live")}else $("server").focus()}catch(_){$("server").focus()}
})();