(()=>{"use strict";
const $=id=>document.getElementById(id);
const PAIR_ENDPOINT="https://ehdvyarueeaetsvzdboo.supabase.co/functions/v1/device-pairing";
let auth=null,view="live",items=[],categories=[],activeCat="all",lastFocus=null,pairing=null,pairTimer=null,renderTimer=null,focusCache=null,pairPollBusy=false,viewGeneration=0;
const WEBOS_RENDER_BATCH=120;
let filteredItems=[],renderedCount=0;
const esc=s=>String(s==null?"":s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
function base(){return auth.server.replace(/\/$/,"")}
function api(action,extra){extra=extra||"";return base()+"/player_api.php?username="+encodeURIComponent(auth.username)+"&password="+encodeURIComponent(auth.password)+(action?"&action="+action:"")+extra}
async function get(url){const r=await fetch(url);if(!r.ok)throw Error("HTTP "+r.status);return r.json()}
async function pairPost(body){const r=await fetch(PAIR_ENDPOINT,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});let d={};try{d=await r.json()}catch(_){d={}}if(!r.ok)throw Error(d.error||("HTTP "+r.status));return d}
function save(){localStorage.setItem("sb.webos.auth",JSON.stringify(auth))}
function invalidateFocus(){focusCache=null}
function focusables(){if(focusCache)return focusCache;focusCache=Array.prototype.slice.call(document.querySelectorAll("button:not([disabled]),input,.card,.cat")).filter(function(x){return x.offsetParent!==null});return focusCache}
function focusFirst(){setTimeout(function(){var f=focusables();if(f.length)f[0].focus()},30)}
function moveFocus(key){
 const all=focusables(),cur=document.activeElement;if(!all.length)return;
 if(all.indexOf(cur)<0){all[0].focus();return}
 const a=cur.getBoundingClientRect(),cx=a.left+a.width/2,cy=a.top+a.height/2;
 let best=null,score=Infinity;
 for(let i=0;i<all.length;i++){const el=all[i];if(el===cur)continue;const r=el.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2,dx=x-cx,dy=y-cy;
  if((key===37&&dx>=-4)||(key===39&&dx<=4)||(key===38&&dy>=-4)||(key===40&&dy<=4))continue;
  const primary=(key===37||key===39)?Math.abs(dx):Math.abs(dy),secondary=(key===37||key===39)?Math.abs(dy):Math.abs(dx),s=primary+secondary*2.2;
  if(s<score){score=s;best=el}}
 if(best){best.focus();try{best.scrollIntoView({block:"nearest",inline:"nearest"})}catch(_){best.scrollIntoView(false)}}
}
async function signin(){
 const server=$("server").value.trim(),username=$("username").value.trim(),password=$("password").value;
 if(!server||!username||!password)return fail("Enter your server, username and password.");
 auth={server:/^https?:\/\//i.test(server)?server:"http://"+server,username:username,password:password};
 $("signin").disabled=true;$("status").textContent="Connecting…";fail("");
 try{const data=await get(api(""));if(!data.user_info||String(data.user_info.auth)!=="1")throw Error("Login rejected");save();showHome()}
 catch(e){fail("Could not sign in: "+e.message);auth=null}
 $("signin").disabled=false;$("status").textContent="";
}
function fail(s){$("error").textContent=s}
function showHome(){
 stopPairing(false);
 view="home";items=[];categories=[];activeCat="all";viewGeneration+=1;invalidateFocus();
 $("login").classList.add("hidden");$("pairing").classList.add("hidden");$("home").classList.add("hidden");$("tvHome").classList.remove("hidden");
 focusFirst();
}
function showContent(){
 invalidateFocus();$("tvHome").classList.add("hidden");$("home").classList.remove("hidden");
}
function showLogin(){
 $("tvHome").classList.add("hidden");$("home").classList.add("hidden");$("pairing").classList.add("hidden");$("login").classList.remove("hidden");invalidateFocus();focusFirst();
}
async function startPairing(){
 fail("");$("login").classList.add("hidden");$("pairing").classList.remove("hidden");$("pairStatus").className="pairStatus";$("pairStatus").textContent="Creating secure pairing…";$("qr").innerHTML="";$("pairCode").textContent="--------";
 try{
   const d=await pairPost({action:"create"});
   pairing={pairingId:d.pairingId,token:d.token,code:d.code};
   $("qr").innerHTML=d.qrSvg||"";
   $("pairCode").textContent=d.code||"";
   $("pairStatus").textContent="Waiting for your phone…";
   $("cancelPair").focus();
   pairTimer=setInterval(function(){pollPairing()},1800);
 }catch(e){
   $("pairStatus").className="pairStatus err";$("pairStatus").textContent="Could not start pairing: "+e.message;$("cancelPair").focus();
 }
}
function b64urlBytes(value){
 value=String(value||"").replace(/-/g,"+").replace(/_/g,"/");
 while(value.length%4)value+="=";
 const bin=atob(value),out=new Uint8Array(bin.length);
 for(let i=0;i<bin.length;i++)out[i]=bin.charCodeAt(i);
 return out;
}
async function decryptPairPayload(ciphertext,nonce,token){
 const keyBytes=b64urlBytes(token),data=b64urlBytes(ciphertext),iv=b64urlBytes(nonce);
 const key=await crypto.subtle.importKey("raw",keyBytes,{name:"AES-GCM"},false,["decrypt"]);
 const plain=await crypto.subtle.decrypt({name:"AES-GCM",iv:iv,tagLength:128},key,data);
 return JSON.parse(new TextDecoder("utf-8").decode(new Uint8Array(plain)));
}
async function pollPairing(){
 if(!pairing||pairPollBusy)return;
 pairPollBusy=true;
 try{
   const d=await pairPost({action:"poll",pairingId:pairing.pairingId,token:pairing.token});
   if(d.status==="pending")return;
   if(d.status==="approved"){
     clearInterval(pairTimer);pairTimer=null;
     $("pairStatus").textContent="Phone approved. Signing in…";
     const payload=await decryptPairPayload(d.ciphertext,d.nonce,pairing.token);
     if(payload.type!=="xtream"||!payload.serverUrl||!payload.username||!payload.password)throw Error("Phone sent invalid account details");
     auth={server:payload.serverUrl,username:payload.username,password:payload.password};
     const check=await get(api(""));
     if(!check.user_info||String(check.user_info.auth)!=="1")throw Error("Provider rejected the linked account");
     save();
     await pairPost({action:"consume",pairingId:pairing.pairingId,token:pairing.token});
     $("pairStatus").className="pairStatus ok";$("pairStatus").textContent="Linked successfully";
     pairing=null;showHome();
     return;
   }
   if(d.status==="cancelled"||d.status==="consumed")throw Error("Pairing is no longer available");
 }catch(e){
   if(pairTimer){clearInterval(pairTimer);pairTimer=null}
   $("pairStatus").className="pairStatus err";$("pairStatus").textContent="Pairing failed: "+e.message;
 }finally{pairPollBusy=false}
}
async function stopPairing(cancelRemote){
 if(pairTimer){clearInterval(pairTimer);pairTimer=null}
 const p=pairing;pairing=null;
 if(cancelRemote&&p){try{await pairPost({action:"cancel",pairingId:p.pairingId,token:p.token})}catch(_){}}
}
async function cancelPairing(){await stopPairing(true);$("pairing").classList.add("hidden");$("login").classList.remove("hidden");$("phoneSignIn").focus()}
async function loadView(v){
 showContent();
 const generation=++viewGeneration;
 view=v;activeCat="all";$("heading").textContent=v==="live"?"Live TV":v==="movies"?"Movies":"Series";
 document.querySelectorAll(".nav[data-view]").forEach(function(b){b.classList.toggle("active",b.dataset.view===v)});
 $("grid").innerHTML="<p>Loading…</p>";
 try{
  const ca=v==="live"?"get_live_categories":v==="movies"?"get_vod_categories":"get_series_categories";
  const ia=v==="live"?"get_live_streams":v==="movies"?"get_vod_streams":"get_series";
  const loaded=await Promise.all([get(api(ca)),get(api(ia))]);if(generation!==viewGeneration)return;categories=loaded[0]||[];items=loaded[1]||[];for(let i=0;i<items.length;i++){items[i].__sbIndex=i;const n=items[i].name!=null?items[i].name:(items[i].title!=null?items[i].title:"");items[i].__sbSearch=String(n).toLowerCase();}renderCats();render();focusFirst()
 }catch(e){if(generation===viewGeneration)$("grid").innerHTML="<p>Unable to load: "+esc(e.message)+"</p>"}
}
function renderCats(){invalidateFocus();$("categories").innerHTML='<button class="cat focusable active" data-cat="all">All</button>'+categories.map(function(c){return '<button class="cat focusable" data-cat="'+esc(c.category_id)+'">'+esc(c.category_name)+"</button>"}).join("")}
function cardHtml(x){
 const name=x.name!=null?x.name:(x.title!=null?x.title:"Untitled"),img=x.stream_icon!=null?x.stream_icon:(x.cover!=null?x.cover:"");
 return '<button class="card focusable" data-i="'+x.__sbIndex+'">'+(img?'<img src="'+esc(img)+'" onerror="this.style.display=\'none\'">':"")+"<strong>"+esc(name)+"</strong><small>"+esc(view==="live"?"Live":view==="movies"?"Movie":"Series")+"</small></button>";
}
function appendNextBatch(){
 if(renderedCount>=filteredItems.length)return;
 const end=Math.min(renderedCount+WEBOS_RENDER_BATCH,filteredItems.length),parts=[];
 for(let i=renderedCount;i<end;i++)parts.push(cardHtml(filteredItems[i]));
 $("grid").insertAdjacentHTML("beforeend",parts.join(""));
 renderedCount=end;invalidateFocus();
}
function render(){
 const q=$("search").value.trim().toLowerCase();
 filteredItems=items.filter(function(x){return(activeCat==="all"||String(x.category_id)===activeCat)&&x.__sbSearch.indexOf(q)>=0});
 renderedCount=0;$("grid").innerHTML="";
 if(!filteredItems.length){$("grid").innerHTML="<p>No results.</p>";invalidateFocus();return}
 appendNextBatch();
}
function play(x){
 if(view==="series")return loadSeries(x);
 const id=x.stream_id||x.num;if(!id)return;
 const ext=view==="live"?"m3u8":(x.container_extension||"mp4");
 const url=base()+"/"+(view==="live"?"live":"movie")+"/"+encodeURIComponent(auth.username)+"/"+encodeURIComponent(auth.password)+"/"+id+"."+ext;
 openVideo(url,x.name!=null?x.name:x.title);
}
async function loadSeries(x){
 $("grid").innerHTML="<p>Loading episodes…</p>";
 try{
  const d=await get(api("get_series_info","&series_id="+encodeURIComponent(x.series_id))),eps=[],groups=d.episodes||{},keys=Object.keys(groups);
  for(let i=0;i<keys.length;i++){const group=groups[keys[i]]||[];for(let j=0;j<group.length;j++)eps.push(group[j])}
  $("grid").innerHTML=eps.map(function(e,i){return '<button class="card focusable" data-episode="'+i+'"><strong>'+esc(e.title||("Episode "+e.episode_num))+"</strong><small>S"+esc(e.season||"")+" E"+esc(e.episode_num||"")+"</small></button>"}).join("");
  $("grid").onclick=function(ev){const b=ev.target.closest("[data-episode]");if(!b)return;const e=eps[parseInt(b.dataset.episode,10)],ext=e.container_extension||"mp4";openVideo(base()+"/series/"+encodeURIComponent(auth.username)+"/"+encodeURIComponent(auth.password)+"/"+e.id+"."+ext,e.title)};
  focusFirst();
 }catch(e){$("grid").innerHTML="<p>Unable to load series.</p>"}
}
function openVideo(url,title){
 lastFocus=document.activeElement;
 $("player").classList.remove("hidden","mini");$("playingTitle").textContent=title||"";$("video").src=url;
 const result=$("video").play();if(result&&result.catch)result.catch(function(){});
 $("nowPlaying").classList.remove("hidden");$("back").focus();
}
function minimizeVideo(){
 if(!$("video").src)return;
 $("player").classList.add("mini");
 if(lastFocus&&lastFocus.offsetParent!==null)lastFocus.focus();else focusFirst();
}
function expandVideo(){
 if(!$("video").src)return;
 $("player").classList.remove("mini","hidden");$("back").focus();
}
function stopVideo(){
 $("video").pause();$("video").removeAttribute("src");$("video").load();$("player").classList.add("hidden");$("player").classList.remove("mini");$("nowPlaying").classList.add("hidden");focusFirst();
}
function activate(el){if(!el)return;if(el.tagName==="INPUT"){el.focus();return}el.click()}
document.addEventListener("click",function(e){
 const nav=e.target.closest("[data-view]");if(nav)return loadView(nav.dataset.view);
 const cat=e.target.closest("[data-cat]");if(cat){activeCat=cat.dataset.cat;document.querySelectorAll(".cat").forEach(function(x){x.classList.toggle("active",x===cat)});render();return}
 const card=e.target.closest("[data-i]");if(card){e.preventDefault();return play(items[parseInt(card.dataset.i,10)])}
});
document.addEventListener("keydown",function(e){
 const k=e.keyCode||e.which;
 if(k===37||k===38||k===39||k===40){e.preventDefault();moveFocus(k);return}
 if(k===13){e.preventDefault();activate(document.activeElement);return}
 if(k===461||e.key==="Backspace"||e.key==="Escape"){
   if(!$("pairing").classList.contains("hidden")){e.preventDefault();cancelPairing();return}
   if(!$("player").classList.contains("hidden")&&!$("player").classList.contains("mini")){e.preventDefault();minimizeVideo();return}
   if(!$("home").classList.contains("hidden")){e.preventDefault();showHome();return}
 }
});
document.addEventListener("click",function(e){const choice=e.target.closest("[data-tv-view]");if(choice){e.preventDefault();loadView(choice.dataset.tvView)}});
$("signin").addEventListener("click",signin);
$("phoneSignIn").addEventListener("click",startPairing);
$("cancelPair").addEventListener("click",cancelPairing);
$("login").addEventListener("submit",function(e){e.preventDefault();signin()});
$("search").oninput=function(){if(renderTimer)clearTimeout(renderTimer);renderTimer=setTimeout(function(){renderTimer=null;render()},120)};
$("grid").onscroll=function(){const g=$("grid");if(g.scrollTop+g.clientHeight>=g.scrollHeight-240)appendNextBatch()};
$("back").onclick=minimizeVideo;
$("nowPlaying").onclick=expandVideo;
function logout(){stopVideo();localStorage.removeItem("sb.webos.auth");auth=null;showLogin()}
$("logout").onclick=logout;$("tvLogout").onclick=logout;
try{const s=JSON.parse(localStorage.getItem("sb.webos.auth")||"null");if(s){auth=s;showHome()}else $("server").focus()}catch(_){$("server").focus()}
})();