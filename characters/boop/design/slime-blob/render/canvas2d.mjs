import {paintFace} from './face-painter.mjs';

export function createCanvas2D(canvas,catalog){
    const faceCanvas=document.createElement('canvas');faceCanvas.width=512;faceCanvas.height=512;
    const faceContext=faceCanvas.getContext('2d');
    const replacement=document.createElement('canvas');replacement.setAttribute('role','img');replacement.setAttribute('aria-label',canvas.getAttribute('aria-label'));canvas.replaceWith(replacement);
    const ctx=replacement.getContext('2d');
    const draw=(channels)=>{
      const {pose,grab,life}=channels;
      const w=replacement.width,h=replacement.height;
      ctx.fillStyle='#000';ctx.fillRect(0,0,w,h);
      const [lean,squash,ripple]=pose,sx=1/Math.sqrt(1+squash*.52),sy=1+squash*.52;
      // A gag's slide carries the dome and its shadow sideways.
      ctx.save();ctx.translate(w*.5,h*.74);ctx.scale(w/4.5,h/3.35);ctx.translate(channels.slide||0,0);
      const shadow=ctx.createRadialGradient(0,0,.1,0,0,1.35);shadow.addColorStop(0,'rgba(0,0,0,.6)');shadow.addColorStop(1,'rgba(0,0,0,0)');ctx.fillStyle=shadow;ctx.save();ctx.scale(1,.21);ctx.beginPath();ctx.arc(0,0,1.4,0,Math.PI*2);ctx.fill();ctx.restore();
      const pull=grab.pull;ctx.translate(pull[0]*.35,-pull[1]*.35-life[0]);ctx.rotate(-life[1]);
      ctx.transform(sx+Math.abs(pull[0])*.12,0,lean*.25-pull[0]*.18,sy+Math.abs(pull[1])*.12,0,0);ctx.beginPath();
      ctx.moveTo(-.95,-.025);ctx.bezierCurveTo(-1.20-ripple*.08,-.18,-1.05,-1.20,-.18,-1.48);ctx.bezierCurveTo(.80,-1.70,1.32,-.65,1.03,-.15);ctx.bezierCurveTo(.99,.15,-.70,.12,-.95,-.025);ctx.closePath();
      const gel=ctx.createRadialGradient(-.25,-.94,.10,.10,-.61,1.15);gel.addColorStop(0,'rgba(109,190,255,.64)');gel.addColorStop(.45,'rgba(48,136,238,.53)');gel.addColorStop(.84,'rgba(61,156,244,.42)');gel.addColorStop(1,'rgba(146,213,255,.66)');ctx.shadowColor='rgba(77,171,255,.50)';ctx.shadowBlur=w*.023;ctx.fillStyle=gel;ctx.fill();ctx.strokeStyle='rgba(146,213,255,.64)';ctx.lineWidth=.015;ctx.stroke();ctx.shadowBlur=0;
      ctx.save();ctx.clip();const shine=ctx.createRadialGradient(-.44,-1.11,0,-.44,-1.11,.37);shine.addColorStop(0,'rgba(248,255,255,.94)');shine.addColorStop(1,'rgba(231,252,255,0)');ctx.fillStyle=shine;ctx.fillRect(-1.4,-1.8,2.8,1.9);ctx.restore();
      paintFace(faceContext,channels,catalog);ctx.drawImage(faceCanvas,-1,-1.54,2,1.66);
      ctx.restore();
    };
    return {draw,canvas:replacement,kind:'procedural-canvas-fallback'};
  }
