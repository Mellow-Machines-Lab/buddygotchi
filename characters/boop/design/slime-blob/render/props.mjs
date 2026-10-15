// The same screen-space prop layout overlays either body renderer. All activity
// positions are above the host's reserved lower 20%; props are persistent objects.
// Each prop's visible is its drawn opacity, ramped by the engine; a prop that is
// fading out still carries the content it last showed.
export function createProps(stage,{hostLane=true}={}) {
  const canvas=document.createElement('canvas');canvas.className='slime-props';canvas.setAttribute('aria-hidden','true');stage.append(canvas);
  const ctx=canvas.getContext('2d');
  function round(x,y,w,h,r,fill,stroke){ctx.beginPath();ctx.roundRect(x,y,w,h,r);if(fill){ctx.fillStyle=fill;ctx.fill();}if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=.002;ctx.stroke();}}
  function text(value,x,y,size,color='#cfeeff',align='center'){ctx.font=`600 ${size}px ui-monospace, SFMono-Regular, monospace`;ctx.textAlign=align;ctx.textBaseline='middle';ctx.fillStyle=color;ctx.fillText(value,x,y);}
  function draw(channels,width,height) {
    if(canvas.width!==width||canvas.height!==height){canvas.width=width;canvas.height=height;}
    ctx.setTransform(width,0,0,height,0,0);ctx.clearRect(0,0,1,1);
    const props=channels.props;if(!props)return;
    ctx.save();ctx.beginPath();ctx.rect(0,0,1,.8);ctx.clip();
    const desk=props.desk;
    if(desk?.visible>0){
      ctx.save();ctx.globalAlpha=desk.visible;
      // The low desk leaves the eyes and mouth unobscured.
      round(.15,.749,.70,.021,.010,'#193b4d','#417587');
      round(.100,.600,.184,.116,.012,'#143748','#64b8cf');
      round(.114,.611,.156,.089,.008,'#071820');
      round(.178,.715,.026,.032,.008,'#345d70');round(.140,.739,.098,.010,.005,'#416b7c');
      const terminal=desk.screen==='terminal',pulse=desk.contact||0,progress=desk.progress||0;
      ctx.strokeStyle='#8cdfcb';ctx.fillStyle='#8cdfcb';ctx.lineWidth=.003;
      if(desk.screen==='searching'){
        const x=.165+.032*progress;ctx.beginPath();ctx.arc(x,.643,.018,0,Math.PI*2);ctx.moveTo(x+.013,.658);ctx.lineTo(x+.028,.675);ctx.stroke();
      }else if(desk.screen==='testing'){
        for(let i=0;i<4;i++){ctx.globalAlpha=desk.visible*(.35+.65*Math.max(0,1-Math.abs(progress*3-i)));ctx.beginPath();ctx.arc(.143+i*.031,.645,.007,0,Math.PI*2);ctx.fill();}ctx.globalAlpha=desk.visible;
        text('TEST',.191,.678,.017,'#70b5bc');
      }else if(desk.screen==='planning'){
        for(let i=0;i<3;i++){round(.130,.627+i*.023,.010,.008,.003,'#8cdfcb');round(.150,.628+i*.023,.063+i*.012,.004,.002,'#70b5bc');}
      }else if(desk.screen==='analyzing'){
        round(.135,.627,.038,.052,.004,'#244758','#70b5bc');round(.190,.627,.038,.052,.004,'#244758','#70b5bc');
        round(.139+progress*.055,.648,.030,.005,.002,'#b2eece');
      }else if(desk.screen==='tool_use'){
        ctx.beginPath();ctx.arc(.178,.647,.016,0,Math.PI*2);ctx.moveTo(.194,.647);ctx.lineTo(.219,.647);ctx.lineTo(.219,.658);ctx.stroke();
        text('·',.178,.647,.021,'#b2eece');
      }else if(desk.screen==='waiting'){
        text('· · ·',.191,.646,.019,'#70b5bc');round(.139,.675,.100,.004,.002,'#345d70');
      }else{
        text(terminal?'> _':'· · ·',.129,.634,.020,'#8cdfcb','left');
        for(let i=0;i<3;i++){ctx.strokeStyle=i===2?'#408b90':'#70b5bc';ctx.lineWidth=.003;ctx.beginPath();ctx.moveTo(.129,.654+i*.013);ctx.lineTo(.129+(.100-i*.024),.654+i*.013);ctx.stroke();}
      }
      if(pulse>.1){round(.129,.682,.045*pulse,.003,.001,'#a4ffe4');}
      round(.387,.713,.258,.030,.008,'#31586b','#7194a0');
      for(let row=0;row<2;row++)for(let key=0;key<9;key++){
        const pressed=pulse>.35&&((desk.side<0&&key===2)||(desk.side>=0&&key===6));
        round(.397+key*.026,.718+row*.010,.019,.006,.002,pressed?'#9bd5df':'#90aab0');
      }
      // Broad gel contacts stay attached to the bottom edge of the body.
      for(const side of (channels.grab.active||channels.life[0]>.025?[]:[-1,1])){
        const contact=side===desk.side?pulse:0;
        const x=.50+side*.078,y=.711+contact*.009;
        const gel=ctx.createLinearGradient(x,y-.029,x,y+.014);gel.addColorStop(0,'#418edf');gel.addColorStop(1,'#9ed5ee');
        ctx.fillStyle=gel;ctx.beginPath();ctx.ellipse(x,y,.031+contact*.008,.013-contact*.005,-side*.13,0,Math.PI*2);ctx.fill();
      }
      ctx.restore();
    }
    const helpers=props.helpers;
    if(helpers?.visible){
      ctx.save();ctx.globalAlpha=helpers.visible;
      const direction=helpers.direction===-1?-1:1,returning=helpers.mode==='return';
      for(let index=0;index<helpers.count;index++){
        const progress=Math.max(0,Math.min(1,helpers.progress||0));
        const inner=.50+direction*.17,outer=.50+direction*(.30+index*.067);
        const x=returning?outer+(inner-outer)*progress:inner+(outer-inner)*progress;
        const y=(direction<0?.51:.645)-(index%2)*.032;
        const gel=ctx.createLinearGradient(x-.02,y-.06,x+.025,y+.025);gel.addColorStop(0,'#438ed3');gel.addColorStop(1,'#96d9ec');
        ctx.fillStyle=gel;ctx.beginPath();ctx.moveTo(x-.032,y+.018);ctx.bezierCurveTo(x-.050,y-.060,x+.040,y-.065,x+.037,y+.018);ctx.quadraticCurveTo(x,y+.039,x-.032,y+.018);ctx.fill();
        for(const side of [-1,1]){ctx.fillStyle='#18354c';ctx.beginPath();ctx.ellipse(x+side*.011,y-.005,.004,.006,0,0,Math.PI*2);ctx.fill();}
      }
      if(helpers.report){const x=direction<0?.13:.775,y=direction<0?.545:.699;round(x,y,.095,.065,.010,'#263f4f','#82bdcf');for(let i=0;i<3;i++)round(x+.017,y+.015+i*.013,.060-i*.014,.004,.002,'#9ac8d4');}
      ctx.restore();
    }
    const listening=props.listening;
    if(listening?.visible){
      const pulse=Math.max(0,Math.min(1,listening.pulse||0));ctx.save();ctx.globalAlpha=listening.visible;
      ctx.strokeStyle='#77c6df';ctx.lineWidth=.004;ctx.beginPath();ctx.arc(.5,.144,.035+pulse*.014,0,Math.PI*2);ctx.stroke();
      round(.492,.119,.016,.031,.008,'#b8e9f5');ctx.beginPath();ctx.arc(.5,.136,.017,0,Math.PI);ctx.moveTo(.5,.153);ctx.lineTo(.5,.164);ctx.stroke();
      text('LISTENING',.5,.223,.026,'#9fcbdc');ctx.restore();
    }
    const start=props.start;
    if(start?.visible){ctx.save();ctx.globalAlpha=start.visible;round(.28,.085,.44,.132,.030,'#1b374e','#78a4c8');text(start.label,.5,.151,.054,'#c5e7fd');ctx.restore();}
    const touch=props.touch;
    if(touch?.visible&&touch.pulse>0){
      ctx.save();ctx.globalAlpha=touch.visible*touch.pulse;ctx.strokeStyle='#b5e9fa';ctx.lineWidth=.004;
      for(let i=0;i<(touch.kind==='tap_spam'?3:1);i++){ctx.beginPath();ctx.arc(.80,.49,.031+i*.013,-.8,.8);ctx.stroke();}ctx.restore();
    }
    const alert=props.alert;
    if(alert?.visible){
      const reveal=alert.reveal??1;ctx.save();ctx.globalAlpha=alert.visible;
      const y=.075+(1-reveal)*.012;
      round(.18,y,.64,.215,.032,'#efbd67','#f8d294');
      if(alert.confirmation>0){ctx.save();ctx.globalAlpha*=alert.confirmation;round(.174,y-.006,.652,.227,.038,null,'#fff4d6');ctx.restore();}
      // Sized to read at arm's length on the device's 2.06" panel.
      text('NEEDS YOU',.5,y+.058,.068,'#2c251d');
      text('Continue on your Mac',.5,y+.152,.054,'#3d2f1f');
      // Knocks are large contact spots, never a new timer.
      if(alert.knock>0){ctx.globalAlpha*=alert.knock;ctx.strokeStyle='#fff1c6';ctx.lineWidth=.007;ctx.beginPath();ctx.arc(.28,y+.171,.013+.010*alert.knock,0,Math.PI*2);ctx.stroke();}
      ctx.restore();
    }
    const result=props.result;
    if(result?.visible){
      const reveal=result.reveal??1,y=.075+(1-reveal)*.016;ctx.save();ctx.globalAlpha=result.visible;
      const good=result.outcome==='success',bad=result.outcome==='failure'||result.state==='error';
      round(.27,y,.46,.210,.030,good?'#173f3b':bad?'#3e2b38':'#243847',good?'#69b49b':bad?'#bf8399':'#83a8bf');
      if(result.trophy){
        ctx.fillStyle='#efc879';ctx.beginPath();ctx.moveTo(.466,y+.031);ctx.lineTo(.534,y+.031);ctx.lineTo(.524,y+.076);ctx.quadraticCurveTo(.500,y+.100,.476,y+.076);ctx.closePath();ctx.fill();
        round(.496,y+.079,.008,.025,.002,'#efc879');round(.476,y+.102,.048,.007,.003,'#efc879');
        ctx.strokeStyle='#efc879';ctx.lineWidth=.006;for(const side of [-1,1]){ctx.beginPath();ctx.arc(.500+side*.037,y+.050,.021,side<0?Math.PI/2:-Math.PI/2,side<0?3*Math.PI/2:Math.PI/2);ctx.stroke();}
      }else if(bad){ctx.strokeStyle='#e8a9b4';ctx.lineWidth=.010;ctx.lineCap='round';ctx.beginPath();ctx.moveTo(.478,y+.036);ctx.lineTo(.522,y+.082);ctx.moveTo(.522,y+.036);ctx.lineTo(.478,y+.082);ctx.stroke();}
      text(result.label,.5,y+.160,.054,good?'#b4e5d4':bad?'#efb9c7':'#d5e8f2');ctx.restore();
    }
    ctx.restore();
    // This lane belongs to host facts, separate from the decorative scene.
    if(hostLane) {
    if(alert?.visible){round(.08,.831,.84,.10,.025,'#161b22');const who=[alert.agent,alert.name||alert.project].filter(Boolean).join(' · ');text(who.slice(0,38)||'Waiting for your response',.5,.878,.025,'#f3d7ab');}
    else if(channels.scene?.quiet){text(channels.scene.state==='no_app'?'Waiting for the app':'Resting',.5,.880,.023,'#59768a');}
    else if(channels.scene?.state){text(channels.scene.state.replaceAll('_',' '),.5,.880,.024,'#7897a9');}
    }
    ctx.setTransform(1,0,0,1,0,0);
  }
  return {canvas,draw};
}
