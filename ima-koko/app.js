import{createClient}from'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const config=window.IMAKOKO_CONFIG||{},configured=config.supabaseUrl?.startsWith('https://')&&!config.supabaseAnonKey?.startsWith('YOUR_');
const $=selector=>document.querySelector(selector),mapSize={width:2072,height:1910};
const venueMap={x:[514.8338934897748,87514.69744314403,-12385714.221532168],y:[151476.22812558583,-11664.858619111323,-4891383.699124284]};
const state={client:null,user:null,pins:[],selected:null,draft:null,layers:null};
const map=L.map('map',{crs:L.CRS.Simple,minZoom:-2,maxZoom:2,zoomSnap:.25,maxBounds:L.latLngBounds([[0,0],[mapSize.height,mapSize.width]]).pad(.15)});
const bounds=[[0,0],[mapSize.height,mapSize.width]];L.imageOverlay('../assets/map2026_2.jpg',bounds).addTo(map);map.fitBounds(bounds,{padding:[6,6]});state.layers=L.layerGroup().addTo(map);

const pointToLatLng=p=>[mapSize.height-p.y,p.x];
const latLngToPoint=ll=>({x:ll.lng,y:mapSize.height-ll.lat});
const gpsToPoint=(lat,lng)=>({x:venueMap.x[0]*lat+venueMap.x[1]*lng+venueMap.x[2],y:venueMap.y[0]*lat+venueMap.y[1]*lng+venueMap.y[2]});
const inside=p=>p.x>=0&&p.x<=mapSize.width&&p.y>=0&&p.y<=mapSize.height;
const name=()=>$('#display-name').value.trim();
const time=iso=>new Intl.DateTimeFormat('ja-JP',{month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'}).format(new Date(iso));
const escapeHtml=s=>String(s).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));

function selectPoint(point,label='地図で選択'){state.selected=point;if(state.draft)state.draft.remove();state.draft=L.marker(pointToLatLng(point),{icon:L.divIcon({className:'',html:'<div class="draft-pin"></div>',iconSize:[28,28],iconAnchor:[14,14]})}).addTo(map);$('#selection').textContent=`${label}しました。「今ここ」で登録できます`;$('#pin-now').disabled=!name()}
map.on('click',event=>selectPoint(latLngToPoint(event.latlng)));

function markerIcon(person,latest){const initial=[...person][0]||'●';return L.divIcon({className:'',html:`<div class="map-pin ${latest?'latest':''}"><span>${escapeHtml(initial)}</span></div>`,iconSize:latest?[42,42]:[34,34],iconAnchor:latest?[21,40]:[17,32]})}
function render(){state.layers.clearLayers();const grouped=new Map;state.pins.forEach(pin=>{if(!grouped.has(pin.display_name))grouped.set(pin.display_name,[]);grouped.get(pin.display_name).push(pin)});const root=$('#people');root.innerHTML='';$('#empty').hidden=state.pins.length>0;for(const[person,pins]of grouped){pins.sort((a,b)=>new Date(b.created_at)-new Date(a.created_at));pins.forEach((pin,index)=>L.marker(pointToLatLng(pin),{icon:markerIcon(person,index===0),zIndexOffset:index===0?500:0}).addTo(state.layers).bindPopup(`<b>${escapeHtml(person)}</b><br>${time(pin.created_at)}${index===0?'<br><strong>最新の場所</strong>':''}`));const card=document.createElement('article');card.className='person';card.innerHTML=`<div class="person-head"><b>${escapeHtml(person)}</b><small>${pins.length}/5本</small></div><div class="history">${pins.map((pin,index)=>`<button data-id="${pin.id}">${index===0?'今ここ ':''}${time(pin.created_at)}</button>`).join('')}</div>`;card.querySelectorAll('button').forEach(button=>button.onclick=()=>{const pin=pins.find(p=>p.id===button.dataset.id);map.flyTo(pointToLatLng(pin),.5);state.layers.eachLayer(layer=>{const ll=layer.getLatLng?.();if(ll&&Math.abs(ll.lng-pin.x)<1&&Math.abs((mapSize.height-ll.lat)-pin.y)<1)layer.openPopup()})});root.append(card)}}

async function load(){const{data,error}=await state.client.from('location_pins').select('*').order('created_at',{ascending:false});if(error)throw error;state.pins=data;render();$('#connection').textContent='● 共有中';$('#connection').className='connection ok'}
async function register(){if(!name()){alert('名前を入力してください');return}if(!state.selected){alert('現在地を取得するか、地図をタップしてください');return}$('#pin-now').disabled=true;try{localStorage.setItem('imakoko-name',name());const{error}=await state.client.from('location_pins').insert({display_name:name(),x:Math.round(state.selected.x*10)/10,y:Math.round(state.selected.y*10)/10});if(error)throw error;state.selected=null;if(state.draft){state.draft.remove();state.draft=null}$('#selection').textContent='登録しました（6本目から最古のピンを自動更新します）';await load()}catch(error){alert(`登録できませんでした：${error.message}`)}finally{$('#pin-now').disabled=!state.selected||!name()}}

$('#display-name').value=localStorage.getItem('imakoko-name')||'';$('#display-name').oninput=()=>$('#pin-now').disabled=!state.selected||!name();$('#save-name').onclick=()=>{if(!name())return;localStorage.setItem('imakoko-name',name());$('#selection').textContent='名前を保存しました'};$('#pin-now').onclick=register;$('#refresh').onclick=load;
$('#locate').onclick=()=>{if(!navigator.geolocation)return alert('この端末では現在地を取得できません');$('#locate').textContent='取得中…';navigator.geolocation.getCurrentPosition(position=>{const point=gpsToPoint(position.coords.latitude,position.coords.longitude);$('#locate').textContent='◎ 現在地を取得';if(!inside(point))return alert('現在地は会場マップの範囲外です');selectPoint(point,'現在地を選択');map.flyTo(pointToLatLng(point),.5)},()=>{$('#locate').textContent='◎ 現在地を取得';alert('現在地を取得できませんでした')},{enableHighAccuracy:true,timeout:10000,maximumAge:30000})};

async function start(){if(!configured){$('#connection').textContent='設定待ち';$('#connection').className='connection error';$('#setup-dialog').showModal();return}try{state.client=createClient(config.supabaseUrl,config.supabaseAnonKey);let{data:{session}}=await state.client.auth.getSession();if(!session){const{data,error}=await state.client.auth.signInAnonymously();if(error)throw error;session=data.session}state.user=session.user;await load();state.client.channel('location-pins').on('postgres_changes',{event:'*',schema:'public',table:'location_pins'},load).subscribe()}catch(error){$('#connection').textContent='接続エラー';$('#connection').className='connection error';alert(`共有サーバーに接続できません：${error.message}`)}}
start();
