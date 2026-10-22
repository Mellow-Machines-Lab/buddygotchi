import {approved} from './approved-presets.mjs';
import {alertEffects} from './alert-presets.mjs';
const n=(at,duration,amp,extra={})=>({at,duration,amp,wave:'noise',lowpass:6500,highpass:800,attack:.0004,decay:duration*.16,...extra});
const t=(at,duration,freq,amp,extra={})=>({at,duration,freq,amp,wave:'sine',attack:.001,decay:duration*.14,...extra});
const r=(duration,...layers)=>({duration,layers:layers.flat()});
const grain=(length,count,amp,hp=700,lp=6000)=>Array.from({length:count},(_,i)=>n(i*length/count,.025+(i%3)*.009,amp*(.75+(i%4)*.08),{highpass:hp,lowpass:lp,decay:.005}));
const brass=(at,duration,f,amp)=>[t(at,duration,f,amp,{wave:'pulse',attack:.012,decay:duration,release:.1,lowpass:3200}),t(at+.006,duration-.006,f*1.006,amp*.3,{wave:'square',attack:.018,decay:duration*.8,release:.1,lowpass:2300}),t(at,duration,f*.5,amp*.32,{wave:'triangle',attack:.012,decay:duration*.5})];
const applause=(at,length)=>Array.from({length:Math.floor(length*19)},(_,i)=>n(at+i/19+((i*7)%5)*.002,.075,.06+(i%3)*.005,{highpass:750,lowpass:5400,decay:.014}));

export const effects={...approved,...alertEffects,
  // Non-melodic failed-attempt sputter. Deliberately NOT the notification ding.
  failedAttempt:r(.74,
    grain(.13,5,.14,1100,6000),
    t(.14,.29,310,.10,{wave:'triangle',end:155,attack:.007,decay:.13}),
    n(.18,.32,.11,{highpass:520,lowpass:3100,attack:.02,decay:.13}),
    t(.37,.25,195,.055,{end:130,attack:.012,decay:.10})),
  brake:r(.32,n(0,.27,.21,{highpass:950,lowpass:6200,attack:.004,decay:.11,filterEnd:.45}),grain(.19,8,.085,1500,5300),t(.01,.13,620,.04,{end:330,decay:.025})),
  wood:r(.13,n(0,.018,.40,{highpass:1200,lowpass:7000,decay:.003}),t(.001,.07,910,.11,{decay:.010}),t(.002,.045,2380,.05,{decay:.006})),
  knock:r(.16,n(0,.018,.39,{highpass:1000,lowpass:5600,decay:.004}),t(.001,.09,690,.14,{decay:.015}),t(.002,.051,1670,.09,{decay:.010})),
  paper:r(.23,grain(.17,7,.16,600,6400)),
  fold:r(.19,n(0,.10,.18,{highpass:1400,lowpass:6900,attack:.005,decay:.025}),grain(.11,4,.14,1100,7200)),
  crumple:r(.27,grain(.21,14,.26,800,8000)),
  tear:r(.23,grain(.17,12,.27,1300,8700)),
  cloth:r(.24,n(0,.20,.17,{highpass:480,lowpass:3900,attack:.020,decay:.075})),
  swipe:r(.27,n(0,.23,.23,{highpass:950,lowpass:6500,attack:.045,decay:.075,filterEnd:.5})),
  slide:r(.25,n(0,.20,.20,{highpass:700,lowpass:4200,attack:.014,decay:.052}),grain(.16,5,.07,1500,4800)),
  ratchet:r(.21,grain(.15,6,.22,1800,7800),t(.003,.036,2270,.045,{decay:.005})),
  motor:r(.26,grain(.20,9,.095,700,3600),t(0,.20,620,.025,{attack:.02,decay:.09})),
  jet:r(.45,n(0,.39,.27,{highpass:450,lowpass:6800,attack:.035,decay:.15,filterEnd:.35}),grain(.22,7,.095,1400,7500)),
  metal:r(.23,n(0,.020,.23,{highpass:1700,lowpass:7800,decay:.003}),t(.001,.16,1840,.080,{decay:.027}),t(.002,.13,3110,.042,{decay:.021}),t(.003,.09,5070,.020,{decay:.014})),
  steam:r(.32,n(0,.28,.30,{highpass:1450,lowpass:7200,attack:.017,decay:.074,filterEnd:.65})),
  latch:r(.09,n(0,.018,.32,{highpass:1800,lowpass:7200,decay:.003}),t(.002,.057,1520,.07,{decay:.007})),
  snip:r(.16,n(0,.025,.34,{highpass:2600,lowpass:10000,decay:.004}),n(.022,.07,.22,{highpass:1100,lowpass:7400,decay:.015}),t(.005,.051,3180,.038,{decay:.006})),
  glass:r(.30,n(0,.021,.61,{highpass:2300,lowpass:11500,decay:.004}),grain(.23,11,.20,2700,10500),t(.011,.12,4190,.03,{decay:.018})),
  pop:r(.10,n(0,.03,.25,{highpass:950,lowpass:5900,decay:.005}),t(.002,.05,1130,.09,{decay:.009})),
  rubber:r(.16,t(0,.12,940,.10,{end:530,decay:.025}),n(.001,.022,.13,{highpass:1700,decay:.004})),
  bubble:r(.23,t(0,.17,370,.12,{end:830,decay:.04}),n(.015,.07,.12,{lowpass:2700,decay:.022})),
  sprinkle:r(.38,grain(.30,9,.11,2100,8500)),
  bell:r(.48,t(0,.40,1420,.14,{decay:.082}),t(.001,.29,2279,.047,{decay:.053}),t(.002,.17,3880,.018,{decay:.025}),n(0,.012,.17,{decay:.002})),
  shimmer:r(.33,t(0,.24,2430,.040,{decay:.048}),t(.042,.23,3460,.025,{decay:.044}),n(.013,.10,.07,{highpass:4000,lowpass:9900,decay:.027})),
  cushion:r(.15,n(0,.12,.12,{highpass:380,lowpass:2500,attack:.006,decay:.032})),
  // The comedy designs' own (comedy-art.mjs), where no material sound fits:
  // a yawn's slow falling tone over a breath, a sneeze's sharp hiss, a
  // snore's soft buzzing breath, and a hiccup's little rising chirp.
  yawn:r(.62,
    t(0,.60,540,.12,{wave:'triangle',end:300,attack:.10,decay:.34,release:.14,lowpass:2000}),
    t(0,.56,1080,.035,{end:600,attack:.10,decay:.24,release:.12}),
    n(.03,.55,.07,{highpass:350,lowpass:2200,attack:.12,decay:.26,release:.14})),
  sneeze:r(.30,
    n(0,.014,.34,{highpass:2400,lowpass:9000,decay:.003}),
    n(.008,.27,.36,{highpass:1500,lowpass:7600,attack:.005,decay:.08,filterEnd:.5}),
    t(.006,.13,460,.06,{wave:'triangle',end:250,decay:.045})),
  snore:r(.60,
    n(0,.56,.34,{hold:150,highpass:110,lowpass:950,attack:.16,decay:.42,release:.16}),
    t(0,.56,128,.07,{wave:'triangle',end:110,attack:.16,decay:.40,release:.16}),
    n(.05,.48,.05,{highpass:700,lowpass:2600,attack:.14,decay:.28,release:.14})),
  hiccup:r(.11,
    n(0,.010,.30,{highpass:1600,lowpass:7000,decay:.0025}),
    t(.003,.075,500,.14,{wave:'triangle',end:920,decay:.022})),
  victoryPodium:r(2.65,
    brass(0,.20,261.63,.075),brass(.80,.20,392,.078),
    ...[261.63,329.63,392,523.25].flatMap((f,i)=>brass(1.60,.78,f,i===3?.145:.075)),
    n(1.59,.85,.20,{highpass:2100,lowpass:11000,decay:.20,release:.20}),
    ...applause(1.71,.83),t(1.60,.40,130.81,.14,{wave:'triangle',decay:.09}))
};

export function effectRecipe(name,pitch=1){
  const base=effects[name];if(!base)throw new Error('Unknown effect: '+name);
  if(pitch===1)return base;
  return {...base,layers:base.layers.map(layer=>({...layer,...(layer.freq?{freq:layer.freq*pitch}:{}),...(layer.end?{end:layer.end*pitch}:{}),...(layer.steps?{steps:layer.steps.map(f=>f*pitch)}:{})}))};
}
