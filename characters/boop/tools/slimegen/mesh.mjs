// Samples the slime's dome and its studio material as a lit mesh, not frames.
// The board projects and deforms these vertices and rasterizes them every
// frame. The material lookup is sampled from equations, not a screenshot.
// Where the camera looks from, as the board's projection has it.
const eye=[0,1.45,3.3];
const add=(a,b)=>a.map((v,i)=>v+b[i]),sub=(a,b)=>a.map((v,i)=>v-b[i]);
const mul=(a,b)=>a.map(v=>v*b),dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
const unit=a=>mul(a,1/Math.hypot(...a));
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const clamp=(x,a=0,b=1)=>Math.min(b,Math.max(a,x));
const smooth=(a,b,x)=>{x=clamp((x-a)/(b-a));return x*x*(3-2*x);};
export function dome(t,p,m=[0,0,0,0]) {
 const sy=Math.sin(t),cy=Math.cos(t),raw=.56+.91*cy;
 let y=.5*(raw+Math.sqrt(raw*raw+.0032))+.019;
 const sx=1/Math.sqrt(Math.max(.76,1+m[1]*.52)),radius=sy*(1.10-.07*cy),h=y/1.49;
 let x=radius*Math.cos(p)*(1+.015*Math.sin(p*3+cy*2)*sy),z=radius*.77*Math.sin(p);
 const ripple=m[2]*.055*sy*Math.sin(p*3+t*2.5);
 x=(x+ripple*Math.cos(p))*sx;z=(z+ripple*Math.sin(p))*sx;y*=1+m[1]*.52;
 x+=m[0]*.34*h*h;z+=m[0]*.09*h;
 const front=smooth(.35,.9,Math.sin(p)),dx=sy*Math.cos(p)*3.9,dy=(cy-.2)*3.1;
 z-=m[3]*.12*Math.exp(-dx*dx-dy*dy)*front;x+=m[3]*.025*x*front;
 return [x,y,z];
}
function shade(t,p,m=[0,0,0,0]) {
 const pos=dome(t,p,m),dt=sub(dome(Math.min(Math.PI-.00001,t+.003),p,m),dome(Math.max(.00001,t-.003),p,m));
 const dp=sub(dome(t,p+.003,m),dome(t,p-.003,m));
 const N=unit(cross(dp,dt)),V=unit(sub(eye,pos)),L=unit(sub([-2.7,4.5,3.3],pos)),H=unit(add(L,V));
 const nl=Math.max(dot(N,L),0),nv=Math.max(dot(N,V),0),eta=1/1.34;
 const I=mul(V,-1),ni=dot(N,I),T=sub(mul(I,eta),mul(N,eta*ni+Math.sqrt(1-eta*eta*(1-ni*ni))));
 const radii=[1.10,.91,.847],q=sub(pos,[0,.56,0]).map((v,i)=>v/radii[i]),d=T.map((v,i)=>v/radii[i]);
 const a=dot(d,d),b=dot(q,d),c=dot(q,q)-1,disc=Math.sqrt(Math.max(b*b-a*c,0));
 const entry=Math.max(0,(-b-disc)/a),exit=Math.max(entry,(-b+disc)/a),thickness=Math.min(exit-entry,2.4),step=thickness/8;
 const throughput=[1,1,1],color=[0,0,0];
 for(let i=0;i<8;++i){let v=add(pos,mul(T,entry+step*(i+.5)));v[1]/=1+m[1]*.52;
  const height=v[1]/1.49;v[0]=(v[0]-m[0]*.34*height*height)*Math.sqrt(Math.max(.76,1+m[1]*.52));v[2]=(v[2]-m[0]*.09*height)*Math.sqrt(Math.max(.76,1+m[1]*.52));
  const inside=smooth(.028,.085,v[1]),corePoint=sub(v,[-.045,.46,-.08]).map((v,i)=>v*[1.6,2.35,2][i]),lightPoint=sub(v,[-.22,.83,-.09]).map((v,i)=>v*[1.05,1.22,1.5][i]);
  const core=Math.exp(-dot(corePoint,corePoint)*1.7),softLight=Math.exp(-dot(lightPoint,lightPoint)*1.25),density=(.024+.025*core)*inside;
  for(let k=0;k<3;++k){color[k]+=throughput[k]*[.04,.29,.85][k]*(.12+.20*core+.32*softLight)*step*inside;throughput[k]*=Math.exp(-[.52,.16,.035][k]*density*step);}
 }
 const R=sub(mul(N,2*nv),V),fresnel=.020+.980*(1-nv)**5,env=smooth(-.20,.80,R[1]);
 const box=unit([-.58,.80,.62]),horizontal=unit(cross(box,[0,1,0])),vertical=cross(horizontal,box);
 const softbox=(1-smooth(.15,.24,Math.abs(dot(R,horizontal))))*(1-smooth(.075,.14,Math.abs(dot(R,vertical))))*smooth(.80,.93,dot(R,box));
 const rimbox=Math.max(dot(R,unit([.90,.38,-.24])),0)**65,spec=Math.max(dot(N,H),0)**145;
 const radiance=color.map((v,k)=>{
  v+=[.008,.055,.15][k]*nl*(.10+.09*thickness);
  v=v*(1-fresnel*.16)+([.08,.20,.44][k]*(1-env)+[.45,.80,1][k]*env)*fresnel*.16;
  v+=[.55,.84,1][k]*(softbox*.10+spec*.08)+[.16,.61,1][k]*rimbox*.23+[.12,.52,1.10][k]*(1-nv)**4*.62;
  return (1-Math.exp(-Math.max(0,v)*1.25))**.454545*(.84+.13*nv**.55);
 });
 // Broad in-surface bloom from the reference's bright-pass composite. The
 // tiny display omits the background blur, rather than drawing halo shells.
 const bloom=1+.5*smooth(.30,.78,Math.max(...radiance));
 return radiance.map(v=>clamp(v*bloom)*255);
}
export function meshCatalog(){
 const rings=24,sectors=32,rows=[],q=x=>Math.round(x*4096);
 for(let row=0;row<=rings;++row)for(let col=0;col<=sectors;++col){
  const t=Math.PI*(.00005+.9999*row/rings),p=Math.PI*2*col/sectors,sy=Math.sin(t),cy=Math.cos(t),pos=dome(t,p),h=pos[1]/1.49;
  const wave=.055*sy*Math.sin(p*3+t*2.5),front=smooth(.35,.9,Math.sin(p));
  rows.push('{'+[...pos.map(q),q(h),q(h*h),q(wave*Math.cos(p)),q(wave*Math.sin(p)),q(sy*Math.cos(p)),q(cy),q(front)].join(',')+'}');
 }
 // The material at two sizes, one after the other: 1025 × 513 texels,
 // under a pixel each across the middle of the dome, so its highlights and
 // rim keep their edges; and half that, 513 × 257, each texel the [1 2 1]
 // blend of the larger's around it, for where the dome turns away and its
 // texels crowd under a pixel (the board reads fewer of them).
 const width=1025,height=513,half=[513,257],levels=[31,63,31];
 const full=new Float64Array(width*height*3);
 for(let y=0;y<height;++y)for(let x=0;x<width;++x){
  const rgb=shade(Math.PI*(.00005+.9999*y/(height-1)),Math.PI*2*x/(width-1));
  for(let k=0;k<3;++k)full[(y*width+x)*3+k]=rgb[k]/255;
 }
 const at=(x,y,k)=>full[(Math.min(height-1,Math.max(0,y))*width+(x+width-1)%(width-1))*3+k];
 const blended=(x,y,k)=>{let sum=0;for(const [dx,wx] of [[-1,1],[0,2],[1,1]])for(const [dy,wy] of [[-1,1],[0,2],[1,1]])sum+=wx*wy*at(2*x+dx,2*y+dy,k);return sum/16;};
 // RGB565 keeps 5/6/5 bits a channel: error diffusion (Floyd–Steinberg, in
 // texture space, so the grain moves with the surface) turns the dark half's
 // bands into an even gradient at no cost to the board.
 const dither=(w,h,value)=>{
  const out=[];let error=Array.from({length:2},()=>Array.from({length:w+2},()=>[0,0,0]));
  for(let y=0;y<h;++y){
   const here=error[y&1],next=error[(y+1)&1];for(const e of next)e.fill(0);
   for(let x=0;x<w;++x){
    const q=[0,0,0];
    for(let k=0;k<3;++k){
     const want=clamp(value(x,y,k)+here[x+1][k]),level=Math.round(want*levels[k]),err=want-level/levels[k];
     q[k]=level;here[x+2][k]+=err*7/16;next[x][k]+=err*3/16;next[x+1][k]+=err*5/16;next[x+2][k]+=err/16;
    }
    out.push((q[0]<<11)|(q[1]<<5)|q[2]);
   }
  }
  return out;
 };
 const big=dither(width,height,(x,y,k)=>full[(y*width+x)*3+k]),small=dither(half[0],half[1],blended);
 const lines=(t,w)=>Array.from({length:t.length/w},(_,i)=>t.slice(i*w,(i+1)*w).join(',')).join(',\n');
 return '// Generated by slimegen/mesh.mjs from the reference dome and material equations. Do not edit.\n#pragma once\n#include <cstdint>\nnamespace slime {\ninline constexpr int kMeshRings='+rings+',kMeshSectors='+sectors+';\nstruct MeshVertex {int16_t x,y,z,h,h2,wx,wz,bx,by,front;};\ninline constexpr MeshVertex kMesh[]={\n'+rows.join(',\n')+'\n};\n// The material, '+width+' × '+height+' texels, then '+half[0]+' × '+half[1]+' from kMaterialHalf.\ninline constexpr int kMaterialWidth='+width+',kMaterialHeight='+height+',kMaterialHalfWidth='+half[0]+',kMaterialHalfHeight='+half[1]+',kMaterialHalf='+big.length+';\ninline constexpr uint16_t kMaterial[]={\n'+lines(big,width)+',\n'+lines(small,half[0])+'\n};\n}\n';
}
