(()=>{"use strict";
const $=id=>document.getElementById(id);
const PAIR_ENDPOINT="https://ehdvyarueeaetsvzdboo.supabase.co/functions/v1/device-pairing";
let auth=null,view="live",items=[],categories=[],activeCat="all",lastFocus=null,pairing=null,pairTimer=null,renderTimer=null,focusCache=null,pairPollBusy=false,viewGeneration=0,playAttempt=0,categoryMode=true,remoteSession=null,remoteTimer=null,remotePollBusy=false,remoteAfterId=0,currentPlayback=null,continueWriteAt=0,episodeSeries=null,episodeQueue=[],episodeIndex=-1;
const WEBOS_RENDER_BATCH=120;
const REMOTE_KEY="sb.webos.remote.v1";
const CONTINUE_KEY="sb.webos.continue.v1";
let filteredItems=[],renderedCount=0;
const esc=s=>String(s==null?"":s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
function base(){return auth.server.replace(/\/$/,"")}
function api(action,extra){extra=extra||"";return base()+"/player_api.php?username="+encodeURIComponent(auth.username)+"&password="+encodeURIComponent(auth.password)+(action?"&action="+action:"")+extra}
async function get(url){const r=await fetch(url);if(!r.ok)throw Error("HTTP "+r.status);return r.json()}
const catalogCache={};
const CATALOG_CACHE_MS=300000;
async function getCached(url){var now=Date.now(),hit=catalogCache[url];if(hit&&now-hit.time<CATALOG_CACHE_MS)return hit.value;var value=await get(url);catalogCache[url]={time:now,value:value};return value}
function cleanCategoryName(value){
 var text=String(value==null?"":value).trim();
 text=text.replace(/\b(?:en|eng|english)\b/gi," ");
 text=text.replace(/[\[\](){}]/g," ");
 text=text.replace(/\s*[|:;_-]+\s*/g," • ");
 text=text.replace(/(?:\s*•\s*){2,}/g," • ");
 text=text.replace(/\s+/g," ").replace(/^\s*•\s*|\s*•\s*$/g,"").trim();
 if(!text)return "Other";
 return text.split(" • ").map(function(part){part=part.trim();if(part.length<=3)return part.toUpperCase();return part.split(" ").map(function(w){return w?w.charAt(0).toUpperCase()+w.slice(1).toLowerCase():w}).join(" ")}).join(" • ");
}
async function pairPost(body){const r=await fetch(PAIR_ENDPOINT,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});let d={};try{d=await r.json()}catch(_){d={}}if(!r.ok)throw Error(d.error||("HTTP "+r.status));return d}
function loadContinue(){
 try{const value=JSON.parse(localStorage.getItem(CONTINUE_KEY)||"[]");return Array.isArray(value)?value:[]}catch(_){return[]}
}
function saveContinue(value){try{localStorage.setItem(CONTINUE_KEY,JSON.stringify(value.slice(0,12)))}catch(_){}}
function removeContinue(id){if(!id)return;saveContinue(loadContinue().filter(function(x){return x&&x.id!==id}));renderTvHome()}
function rememberPlayback(force){
 const video=$("video"),meta=currentPlayback;if(!meta||meta.live||!video||!isFinite(video.duration)||video.duration<=0)return;
 const now=Date.now();if(!force&&now-continueWriteAt<4000)return;continueWriteAt=now;
 const position=Math.floor(video.currentTime||0),duration=Math.floor(video.duration||0);if(position<8||duration<20)return;
 if(position/duration>=.95){removeContinue(meta.id);return}
 const list=loadContinue().filter(function(x){return x&&x.id!==meta.id});
 list.unshift({id:meta.id,title:meta.title||"Untitled",subtitle:meta.subtitle||"",artwork:meta.artwork||"",url:meta.url||video.currentSrc||video.src,position:position,duration:duration,updatedAt:Date.now()});
 saveContinue(list);renderTvHome();
}
function renderTvHome(){
 const list=loadContinue(),hero=list.length?list[0]:null,wrap=$("tvContinue"),section=$("tvContinueSection"),heroButton=$("tvHeroPlay");
 if(hero){$("tvHeroTitle").textContent=hero.title||"Continue watching";$("tvHeroSubtitle").textContent=hero.subtitle||"Pick up where you left off.";heroButton.classList.remove("hidden");heroButton.onclick=function(){resumeHistory(0)}}
 else{$("tvHeroTitle").textContent="What do you want to watch?";$("tvHeroSubtitle").textContent="Live TV, movies and series in one place.";heroButton.classList.add("hidden")}
 if(!list.length){section.classList.add("hidden");wrap.innerHTML="";return}
 section.classList.remove("hidden");
 wrap.innerHTML=list.slice(0,8).map(function(x,i){const pct=x.duration>0?Math.max(0,Math.min(100,(x.position/x.duration)*100)):0;return '<button class="resumeCard focusable" data-resume="'+i+'">'+(x.artwork?'<img class="resumeArt" src="'+esc(x.artwork)+'" onerror="this.style.display=\'none\'">':"")+'<span class="resumeShade"></span><span class="resumeText"><strong>'+esc(x.title||"Continue watching")+'</strong><small>'+esc(x.subtitle||"Resume")+'</small><span class="resumeProgress"><span style="width:'+pct+'%"></span></span></span></button>'}).join("");
 invalidateFocus();
}
function resumeHistory(index){const item=loadContinue()[index];if(!item||!item.url)return;openVideo(item.url,item.title||"Continue watching",false,{id:item.id,title:item.title,subtitle:item.subtitle,artwork:item.artwork,url:item.url,live:false});setTimeout(function(){try{$("video").currentTime=Number(item.position||0)}catch(_){}},800)}
function loadRemoteSession(){if(remoteSession)return remoteSession;try{const value=JSON.parse(localStorage.getItem(REMOTE_KEY)||"null");if(value&&value.pairingId&&value.token)remoteSession=value}catch(_){}return remoteSession}
function clearRemoteSession(){remoteSession=null;remoteAfterId=0;try{localStorage.removeItem(REMOTE_KEY)}catch(_){}if(remoteTimer){clearInterval(remoteTimer);remoteTimer=null}}
function startRemotePolling(){if(!loadRemoteSession()||remoteTimer)return;remoteTimer=setInterval(function(){pollRemote()},300);pollRemote()}
async function pollRemote(){
 const session=loadRemoteSession();if(!session||remotePollBusy)return;remotePollBusy=true;
 try{const d=await pairPost({action:"remote_poll",pairingId:session.pairingId,token:session.token,afterId:remoteAfterId});const commands=d.commands||[];for(let i=0;i<commands.length;i++){const row=commands[i];handleRemoteCommand(row.command);remoteAfterId=Math.max(remoteAfterId,Number(row.id||0))}}
 catch(e){const msg=String(e&&e.message||e);if(/expired|not found|invalid pairing|not active/i.test(msg))clearRemoteSession()}
 finally{remotePollBusy=false}
}
function goBack(){
 if(!$("pairing").classList.contains("hidden")){cancelPairing();return}
 if(!$("player").classList.contains("hidden")&&!$("player").classList.contains("mini")){minimizeVideo();return}
 if(!$("home").classList.contains("hidden")){if(!categoryMode){categoryMode=true;activeCat="all";renderCategoryGrid();focusFirst();return}showHome();return}
}
function handleRemoteCommand(command){
 if(command==="up")return moveFocus(38);if(command==="down")return moveFocus(40);if(command==="left")return moveFocus(37);if(command==="right")return moveFocus(39);
 if(command==="select")return activate(document.activeElement);if(command==="back")return goBack();if(command==="home")return showHome();if(command==="refresh")return refreshProvider();
 if(command==="play_pause"){const video=$("video");if(!video||$("player").classList.contains("hidden"))return;if(video.paused){const p=video.play();if(p&&p.catch)p.catch(function(){})}else video.pause()}
}
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
 stopPairing(false);view="home";items=[];categories=[];activeCat="all";categoryMode=true;viewGeneration+=1;invalidateFocus();
 $("login").classList.add("hidden");$("pairing").classList.add("hidden");$("home").classList.add("hidden");$("tvHome").classList.remove("hidden");
 renderTvHome();startRemotePolling();focusFirst();
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
     remoteSession={pairingId:pairing.pairingId,token:pairing.token,code:pairing.code||""};
     localStorage.setItem(REMOTE_KEY,JSON.stringify(remoteSession));remoteAfterId=0;startRemotePolling();
     $("pairStatus").className="pairStatus ok";$("pairStatus").textContent="Linked successfully";
     pairing=null;showHome();return;
   }
   if(d.status==="cancelled"||d.status==="consumed")throw Error("Pairing is no longer available");
 }catch(err){
   if(pairTimer){clearInterval(pairTimer);pairTimer=null}
   $("pairStatus").className="pairStatus err";$("pairStatus").textContent="Pairing failed: "+err.message;
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
 view=v;activeCat="all";categoryMode=true;$("heading").textContent=v==="live"?"Live TV":v==="movies"?"Movies":"Series";
 $("grid").onclick=null;$("grid").innerHTML="<p>Loading…</p>";
 try{
  const ca=v==="live"?"get_live_categories":v==="movies"?"get_vod_categories":"get_series_categories";
  const ia=v==="live"?"get_live_streams":v==="movies"?"get_vod_streams":"get_series";
  const loaded=await Promise.all([getCached(api(ca)),getCached(api(ia))]);if(generation!==viewGeneration)return;
  categories=loaded[0]||[];items=loaded[1]||[];
  for(let i=0;i<items.length;i++){items[i].__sbIndex=i;const n=items[i].name!=null?items[i].name:(items[i].title!=null?items[i].title:"");items[i].__sbSearch=String(n).toLowerCase()}
  renderCategoryGrid();focusFirst();
 }catch(err){if(generation===viewGeneration)$("grid").innerHTML="<p>Unable to load: "+esc(err.message)+"</p>"}
}
function renderCategoryGrid(){
 categoryMode=true;invalidateFocus();$("grid").classList.add("categoryMode");
 const q=$("search").value.trim().toLowerCase();
 const visible=categories.filter(function(x){return !q||String(x.category_name||"").toLowerCase().indexOf(q)>=0});
 const list=[{category_id:"all",category_name:"All"}].concat(visible);
 $("grid").innerHTML=list.map(function(cat){
   const id=String(cat.category_id||"all"),name=cleanCategoryName(cat.category_name||"All");
   let sample=null;for(let i=0;i<items.length;i++){if(id==="all"||String(items[i].category_id)===id){sample=items[i];break}}
   const img=sample?(sample.stream_icon||sample.cover||""):"";
   return '<button class="categoryCard focusable" data-category="'+esc(id)+'">'+(img?'<img class="categoryArt" src="'+esc(img)+'" onerror="this.style.display=\'none\'">':"")+'<span class="categoryShade"></span><span class="categoryName">'+esc(name)+'</span></button>';
 }).join("");
}
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
 if(categoryMode)return renderCategoryGrid();
 $("grid").classList.remove("categoryMode");
 const q=$("search").value.trim().toLowerCase();
 filteredItems=items.filter(function(x){return(activeCat==="all"||String(x.category_id)===activeCat)&&x.__sbSearch.indexOf(q)>=0});
 renderedCount=0;$("grid").innerHTML="";
 if(!filteredItems.length){$("grid").innerHTML="<p>No results.</p>";invalidateFocus();return}
 appendNextBatch();
}
function play(x){
 if(view==="series")return loadSeries(x);
 const id=x.stream_id||x.num;if(!id)return;
 const root=base()+"/"+(view==="live"?"live":"movie")+"/"+encodeURIComponent(auth.username)+"/"+encodeURIComponent(auth.password)+"/"+id;
 const title=x.name!=null?x.name:x.title;
 if(view==="live")openVideoCandidates([root+".m3u8",root+".ts"],title,false,{id:"live:"+id,title:title,live:true});
 else{
   const url=root+"."+(x.container_extension||"mp4");
   openVideoCandidates([url],title,false,{id:"movie:"+id,title:title,subtitle:"Movie",artwork:x.stream_icon||x.cover||"",url:url,live:false});
 }
}
async function loadSeries(x){
 episodeSeries=x;
 $("grid").innerHTML="<p>Loading episodes…</p>";
 try{
  const d=await get(api("get_series_info","&series_id="+encodeURIComponent(x.series_id))),eps=[],groups=d.episodes||{},keys=Object.keys(groups);
  for(let i=0;i<keys.length;i++){const group=groups[keys[i]]||[];for(let j=0;j<group.length;j++)eps.push(group[j])}
  $("grid").innerHTML=eps.map(function(e,i){return '<button class="card focusable" data-episode="'+i+'"><strong>'+esc(e.title||("Episode "+e.episode_num))+"</strong><small>S"+esc(e.season||"")+" E"+esc(e.episode_num||"")+"</small></button>"}).join("");
  episodeQueue=eps;episodeIndex=-1;
  $("grid").onclick=function(ev){const b=ev.target.closest("[data-episode]");if(!b)return;playEpisode(parseInt(b.dataset.episode,10))};
  focusFirst();
 }catch(e){$("grid").innerHTML="<p>Unable to load series.</p>"}
}
function playEpisode(index){
 if(index<0||index>=episodeQueue.length)return;
 episodeIndex=index;
 const e=episodeQueue[index],ext=e.container_extension||"mp4";
 const url=base()+"/series/"+encodeURIComponent(auth.username)+"/"+encodeURIComponent(auth.password)+"/"+e.id+"."+ext;
 const title=e.title||("Episode "+e.episode_num);
 openVideo(url,title,true,{id:"episode:"+e.id,title:title,subtitle:episodeSeries&&episodeSeries.name?episodeSeries.name:"Series",artwork:episodeSeries&&(episodeSeries.cover||episodeSeries.stream_icon)||"",url:url,live:false});
}
function playNextEpisode(){
 if(episodeIndex>=0&&episodeIndex+1<episodeQueue.length)playEpisode(episodeIndex+1);
}
function mediaType(url){
 if(/\.m3u8(?:\?|$)/i.test(url))return "application/vnd.apple.mpegurl";
 if(/\.ts(?:\?|$)/i.test(url))return "video/mp2t";
 if(/\.mkv(?:\?|$)/i.test(url))return "video/x-matroska";
 return "video/mp4";
}
function resetVideo(video){
 try{rememberPlayback(true)}catch(_){}
 try{video.pause()}catch(_){}
 video.onerror=null;video.onplaying=null;video.oncanplay=null;video.onended=null;video.ontimeupdate=null;
 while(video.firstChild)video.removeChild(video.firstChild);
 video.removeAttribute("src");video.load();
}
function openVideoCandidates(urls,title,autoNext,meta){
 lastFocus=document.activeElement;playAttempt+=1;var attempt=playAttempt,index=0,video=$("video"),timer=null;
 currentPlayback=meta||null;continueWriteAt=0;
 $("player").classList.remove("hidden","mini");$("playingTitle").textContent=(title||"")+" — Loading…";
 function clearTimer(){if(timer){clearTimeout(timer);timer=null}}
 function next(){
  clearTimer();if(attempt!==playAttempt)return;
  if(index>=urls.length){$("playingTitle").textContent=(title||"")+" — Playback failed";return}
  var url=urls[index++],settled=false;resetVideo(video);
  if(currentPlayback&&!currentPlayback.url)currentPlayback.url=url;
  video.onerror=function(){if(!settled){settled=true;next()}};
  video.onplaying=function(){settled=true;clearTimer();$("playingTitle").textContent=title||""};
  video.ontimeupdate=function(){rememberPlayback(false)};
  video.onended=function(){clearTimer();rememberPlayback(true);if(currentPlayback&&!currentPlayback.live)removeContinue(currentPlayback.id);if(autoNext)playNextEpisode()};
  video.oncanplay=function(){var p=video.play();if(p&&p.catch)p.catch(function(){})};
  var source=document.createElement("source");source.setAttribute("src",url);source.setAttribute("type",mediaType(url));video.appendChild(source);
  video.load();var p=video.play();if(p&&p.catch)p.catch(function(){});
  timer=setTimeout(function(){if(!settled){settled=true;next()}},10000);
 }
 next();$("nowPlaying").classList.remove("hidden");$("back").focus();
}
function openVideo(url,title,autoNext,meta){openVideoCandidates([url],title,!!autoNext,meta)}
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
 try{rememberPlayback(true)}catch(_){}
 playAttempt+=1;currentPlayback=null;resetVideo($("video"));$("player").classList.add("hidden");$("player").classList.remove("mini");$("nowPlaying").classList.add("hidden");focusFirst();
}
function activate(el){if(!el)return;if(el.tagName==="INPUT"){el.focus();return}el.click()}
document.addEventListener("click",function(e){
 const choice=e.target.closest("[data-tv-view]");if(choice){e.preventDefault();return loadView(choice.dataset.tvView)}
 const homeBtn=e.target.closest("[data-tv-home]");if(homeBtn){e.preventDefault();return showHome()}
 const nav=e.target.closest("[data-view]");if(nav){if(nav.id==="nowPlaying")return expandVideo();return loadView(nav.dataset.view)}
 const category=e.target.closest("[data-category]");if(category){activeCat=category.dataset.category;categoryMode=false;const match=categories.find(function(x){return String(x.category_id)===activeCat});$("heading").textContent=(view==="live"?"Live TV":view==="movies"?"Movies":"Series")+" • "+(activeCat==="all"?"All":cleanCategoryName(match&&match.category_name||"Category"));render();focusFirst();return}
 const resume=e.target.closest("[data-resume]");if(resume){e.preventDefault();return resumeHistory(parseInt(resume.dataset.resume,10))}
 const cat=e.target.closest("[data-cat]");if(cat){activeCat=cat.dataset.cat;categoryMode=false;render();return}
 const card=e.target.closest("[data-i]");if(card){e.preventDefault();return play(items[parseInt(card.dataset.i,10)])}
});
document.addEventListener("keydown",function(e){
 const k=e.keyCode||e.which;
 if(k===37||k===38||k===39||k===40){e.preventDefault();moveFocus(k);return}
 if(k===13){e.preventDefault();activate(document.activeElement);return}
 if(k===461||e.key==="Backspace"||e.key==="Escape"){e.preventDefault();goBack();return}
});
$("signin").addEventListener("click",signin);
$("phoneSignIn").addEventListener("click",startPairing);
$("cancelPair").addEventListener("click",cancelPairing);
$("login").addEventListener("submit",function(e){e.preventDefault();signin()});
$("search").oninput=function(){if(renderTimer)clearTimeout(renderTimer);renderTimer=setTimeout(function(){renderTimer=null;if(categoryMode)renderCategoryGrid();else render()},120)};
$("grid").onscroll=function(){const g=$("grid");if(g.scrollTop+g.clientHeight>=g.scrollHeight-240)appendNextBatch()};
$("back").onclick=minimizeVideo;
$("nowPlaying").onclick=expandVideo;
function logout(){stopVideo();localStorage.removeItem("sb.webos.auth");auth=null;showLogin()}
async function refreshProvider(){
 var b=$("tvRefresh");if(b){b.disabled=true;b.textContent="Refreshing…"}
 for(var key in catalogCache){if(Object.prototype.hasOwnProperty.call(catalogCache,key))delete catalogCache[key]}
 items=[];categories=[];filteredItems=[];renderedCount=0;viewGeneration+=1;
 try{await get(api(""));if(b)b.textContent="✓ Refreshed"}
 catch(e){if(b)b.textContent="Refresh failed"}
 setTimeout(function(){if(b){b.disabled=false;b.textContent="↻ Refresh";b.focus()}},1200);
}
$("logout").onclick=logout;$("tvLogout").onclick=logout;$("tvRefresh").onclick=refreshProvider;
try{const s=JSON.parse(localStorage.getItem("sb.webos.auth")||"null");loadRemoteSession();if(s){auth=s;showHome()}else $("server").focus()}catch(_){$("server").focus()}
})();