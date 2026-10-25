// Procedural nonverbal review sketches. No recorded/sample/model assets.
// Pure render() is shared by browser audition and offline checks.
(function(global){
  'use strict';
  const recipes={squish:.23,bounce:.32,wobble:.38,poke:.13,keyboard:.08,tear:.14,knock:.13,ding:.68,knock_ding:1.1,complete:2,cheer:2.6,failed:1.05,
    sneeze:.3,breath:.55};
  const clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
  const finite=(n,fallback)=>Number.isFinite(n)?n:fallback;
  function render(name, options={}){
    if(!Object.hasOwn(recipes,name))throw new RangeError('Unknown slime effect: '+name);
    const sampleRate=clamp(Math.round(finite(options.sampleRate,22050)),8000,48000);
    const variant=clamp(Math.floor(finite(options.variant,0)),0,2);
    const pitch=clamp(finite(options.pitch,1),.7,1.4);
    const gain=clamp(finite(options.gain,.45),0,.8);
    let seed=finite(options.seed,1729)>>>0;
    const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
    const data=new Float32Array(Math.ceil(recipes[name]*sampleRate));
    const noise=()=>rand()*2-1;
    const sweep=(t,f,end,decay)=>Math.sin(2*Math.PI*(end*t+(f-end)*(1-Math.exp(-decay*t))/decay));
    const bell=(t,f,decay)=>t<0?0:(Math.sin(t*f*2*Math.PI)+.34*Math.sin(t*f*2.76*2*Math.PI))*Math.exp(-t*decay);
    const impulse=(t,f,decay)=>t<0?0:Math.sin(t*f*2*Math.PI)*Math.exp(-t*decay);
    let low=0,band=0;
    for(let i=0;i<data.length;i++){
      const t=i/sampleRate,n=noise();low+=.075*(n-low);band+=.38*(n-band);
      const pp=pitch*(.98+variant*.02);
      let value=0;
      switch(name){
        case 'squish':value=.48*sweep(t,245*pp,58*pp,18)*Math.exp(-t*20)+low*.8*Math.exp(-t*17);break;
        case 'bounce':value=.55*sweep(t,330*pp,90*pp,22)*Math.exp(-t*15)+.23*sweep(t,140*pp,300*pp,12)*Math.exp(-t*19)+band*.12*Math.exp(-t*45);break;
        case 'wobble':value=.40*Math.sin(2*Math.PI*(125*pp*t+.8*Math.sin(t*24)))*Math.exp(-t*11)+low*.15*Math.exp(-t*18);break;
        case 'poke':value=.38*sweep(t,510*pp,155*pp,38)*Math.exp(-t*32)+band*.18*Math.exp(-t*60);break;
        case 'keyboard':value=(n-low)*.47*Math.exp(-t*100)+impulse(t-.006,1350*pp,130)*.24+impulse(t-.019,700*pp,150)*.20;break;
        case 'tear':value=.30*sweep(t,900*pp,360*pp,32)*Math.exp(-t*34)+low*.16*Math.exp(-t*60);break;
        case 'knock':value=.50*impulse(t,185*pp,52)+band*.25*Math.exp(-t*90);break;
        case 'ding':value=.44*bell(t,880,5.6)+.37*bell(t-.20,1318.51,6.4);break;
        case 'knock_ding':{
          const count=variant+1;
          for(let k=0;k<count;k++){
            const a=t-(.04+k*.11);
            if(a>=0)value+=.50*impulse(a,185*pitch,52)+band*.25*Math.exp(-a*90);
          }
          // Stable alert identity; mood pitch never retunes these notes.
          value+=.44*bell(t-.42,880,5.6)+.37*bell(t-.62,1318.51,6.4);break;
        }
        case 'complete':{
          const notes=[523.25,659.25,783.99,1046.5];
          for(let k=0;k<notes.length;k++)value+=.16*bell(t-k*.115,notes[k],2.5);
          if(t>.45){const a=t-.45;value+=.14*(impulse(a,261.63,1.7)+impulse(a,392,1.9)+impulse(a,523.25,2.2));}
          // Airy nonverbal celebration swell; not a crowd/voice sample.
          value+=low*.42*Math.pow(Math.sin(Math.PI*clamp(t/2,0,1)),2);break;
        }
        // A big finish: two bright chord stabs, a held major chord, a run up
        // to a sparkle, over a rattle of soft claps. Nonverbal, no crowd.
        case 'cheer':{
          const stab=(a,notes,d)=>{let v=0;for(const f of notes)v+=impulse(a,f,d)+.3*impulse(a,f*2,d*1.4);return v;};
          if(t<.24)value+=.15*stab(t,[523.25,659.25,783.99],7);
          if(t>=.2&&t<.44)value+=.15*stab(t-.2,[698.46,880,1046.5],7);
          if(t>=.4)value+=.12*stab(t-.4,[523.25,659.25,783.99,1046.5],1.5);
          const run=[1046.5,1318.51,1567.98,2093];
          for(let k=0;k<run.length;k++)value+=.08*bell(t-.55-k*.07,run[k],4);
          for(let k=0;k<36;k++){
            const at=.42+((k*.618034+variant*.137)%1)*1.75,a=t-at;
            if(a>=0&&a<.05)value+=band*.55*Math.exp(-a*70)*(1-clamp((t-1.9)/.7,0,1));
          }
          break;
        }
        case 'failed':value=.43*bell(t,392,5.4)+.32*bell(t-.19,293.66,5.2)+.24*impulse(t-.40,110*pitch,7)+low*.24*Math.exp(-t*10);break;
        // A tiny gel sneeze: a short rising "ah", then an airy "choo".
        case 'sneeze':{
          const ah=t<.09?.20*Math.sin(2*Math.PI*(360*pp*t+1100*pp*t*t))*Math.sin(Math.PI*t/.09):0;
          value=ah+(t<.08?0:(band*.50+(n-low)*.22)*Math.exp(-(t-.08)*20));break;
        }
        // A snore's soft breath: low airy noise that swells and fades, with a faint purr.
        case 'breath':{
          const swell=Math.pow(Math.sin(Math.PI*clamp(t/.55,0,1)),2);
          value=(low*1.6+band*.06)*swell+.09*Math.sin(2*Math.PI*58*pp*t)*swell*(.6+.4*Math.sin(2*Math.PI*11*t));break;
        }
      }
      const attack=clamp(t/.003,0,1), release=clamp((recipes[name]-t)/.014,0,1);
      data[i]=Math.tanh(value)*gain*attack*release;
    }
    return {name,variant,sampleRate,duration:data.length/sampleRate,data};
  }
  let context=null,active=new Set();
  async function play(name,options={}){
    const Audio=global.AudioContext||global.webkitAudioContext;
    if(!Audio)throw new Error('Web Audio is unavailable; render() still works offline.');
    context=context||new Audio();
    await context.resume();
    // The manual audition plays one whole cue at a time, avoiding stacks.
    stop();
    const clip=render(name,{...options,sampleRate:context.sampleRate});
    const buffer=context.createBuffer(1,clip.data.length,clip.sampleRate);buffer.copyToChannel(clip.data,0);
    const source=context.createBufferSource(),level=context.createGain();
    source.buffer=buffer;source.connect(level);level.connect(context.destination);
    const handle={source,level};active.add(handle);
    source.onended=()=>{source.disconnect();level.disconnect();active.delete(handle);};source.start();
    return {name,variant:clip.variant,duration:clip.duration};
  }
  function stop(){
    for(const handle of active){
      const now=context.currentTime;
      handle.level.gain.cancelScheduledValues(now);handle.level.gain.setValueAtTime(handle.level.gain.value,now);
      handle.level.gain.linearRampToValueAtTime(0,now+.012);handle.source.stop(now+.015);
    }
    active.clear();
  }
  const api={recipes,render,play,stop};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
  else global.SlimeSFX=api;
})(typeof window!=='undefined'?window:globalThis);
