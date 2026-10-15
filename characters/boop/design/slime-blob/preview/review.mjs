// Records the rendered preview itself, never a webcam or the user's desktop.
// Captures remain local Blob URLs until the owner/reviewer downloads them.
export function createReview({root,body,props,getChannels,applyCase,cases,startRun,getCases}) {
  const button=root.querySelector('[data-record]'),status=root.querySelector('[data-record-status]'),gallery=root.querySelector('[data-review-gallery]');
  const capture=document.createElement('canvas'),ctx=capture.getContext('2d');
  let recording=null,cursor=0,startedAt=0,active=false,stream=null,generation=0;
  const saveButton=root.querySelector('[data-save-review]');
  let localSave=null,clips=[],complete=false;
  function updateSave(){saveButton.disabled=active||!complete||clips.length!==cases.length||!localSave?.enabled;}
  if(location.protocol==='http:')fetch('/review-capture-config').then(response=>response.ok?response.json():null).then(config=>{localSave=config;updateSave();}).catch(()=>{});
  const durationMs=6400;
  const controls=[...root.querySelectorAll('button,select')].filter(control=>control!==button&&control!==saveButton);
  function setBusy(value){for(const control of controls)control.disabled=value;updateSave();}
  function begin(item,now){
    applyCase(item);capture.width=960;capture.height=Math.round(960*body().height/body().width)+48;
    stream=capture.captureStream(30);
    const type=['video/webm;codecs=vp9','video/webm;codecs=vp8','video/webm'].find(t=>MediaRecorder.isTypeSupported(t));
    const recorder=new MediaRecorder(stream,type?{mimeType:type,videoBitsPerSecond:1400000}:{videoBitsPerSecond:1400000});
    const chunks=[],run=generation;recording=recorder;startedAt=now;
    recorder.addEventListener('dataavailable',event=>{if(event.data.size)chunks.push(event.data);});
    recorder.addEventListener('stop',()=>{
      if(run!==generation)return;
      const blob=new Blob(chunks,{type:recorder.mimeType||'video/webm'}),url=URL.createObjectURL(blob);
      const card=document.createElement('article'),title=document.createElement('p'),video=document.createElement('video'),link=document.createElement('a');
      title.textContent=item.id;video.controls=true;video.muted=true;video.preload='metadata';video.src=url;
      link.href=url;link.download=item.id+'.webm';link.textContent='Save '+item.id;card.append(title,video,link);gallery.append(card);
      clips.push({name:item.id+'.webm',blob});updateSave();
    });
    recorder.start();status.textContent=`Recording ${cursor+1}/${cases.length}: ${item.id}`;
  }
  function end(){if(recording?.state==='recording')recording.stop();stream?.getTracks().forEach(track=>track.stop());recording=null;stream=null;}
  button.addEventListener('click',()=>{
    if(active){active=false;end();setBusy(false);button.textContent='Record review set';status.textContent='Recording stopped; captured clips remain below, including the partial last clip.';return;}
    if(getCases)cases=getCases();
    if(!cases.length){status.textContent='No verified review cases are available.';return;}
    if(typeof MediaRecorder==='undefined'){status.textContent='Canvas recording is unavailable in this browser.';return;}
    for(const link of gallery.querySelectorAll('a'))URL.revokeObjectURL(link.href);
    generation++;gallery.replaceChildren();clips=[];complete=false;startRun();cursor=0;active=true;setBusy(true);startedAt=0;button.textContent='Stop recording';status.textContent='Preparing review captures…';
  });
  saveButton.addEventListener('click',async()=>{
    if(saveButton.disabled)return;saveButton.disabled=true;button.disabled=true;
    try{
      for(const [index,clip] of clips.entries()){
        status.textContent=`Saving ${index+1}/${clips.length}: ${clip.name}`;
        const response=await fetch('/review-captures/'+encodeURIComponent(clip.name),{method:'POST',headers:{'Content-Type':'video/webm','X-Boop-Review-Token':localSave.token},body:clip.blob});
        if(!response.ok)throw Error(`${clip.name}: ${response.status===409?'file already exists; choose a fresh capture directory':'save failed ('+response.status+')'}`);
      }
      status.textContent=`Saved ${clips.length} WebM clips in ${localSave.directory}. Art review is pending.`;
    }catch(error){status.textContent=error.message;updateSave();}finally{button.disabled=false;}
  });
  return {
    get active(){return active;},
    tick(now){
      if(!active)return;
      if(!recording){
        try{begin(cases[cursor],now);}catch(error){active=false;end();setBusy(false);button.textContent='Record review set';status.textContent='Recording unavailable: '+error.message;return;}
      }
      ctx.fillStyle='#080b10';ctx.fillRect(0,0,capture.width,capture.height);
      ctx.drawImage(body(),0,48,capture.width,capture.height-48);ctx.drawImage(props.canvas,0,48,capture.width,capture.height-48);
      ctx.font='20px ui-monospace, monospace';ctx.textAlign='left';ctx.fillStyle='#dceefa';ctx.fillText(cases[cursor].id,22,31);
      const channels=getChannels();ctx.font='14px ui-monospace, monospace';ctx.textAlign='right';ctx.fillStyle='#94aabb';
      const phase=cases[cursor].from?(channels.bridge?.primitive||'prepare edge'):channels.scene?.phase||'idle';
      ctx.fillText(`${phase} · silent art review`,938,31);
      if(now-startedAt>=durationMs){end();cursor++;if(cursor===cases.length){active=false;complete=true;setBusy(false);button.textContent='Record review set';status.textContent=`Ready: ${cases.length} local preview clips. Art review is pending.`;} }
    }
  };
}
