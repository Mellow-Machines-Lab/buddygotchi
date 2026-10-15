// Camera shared by drawing and pointer hit testing.
export function matrixMultiply(a,b){
    const out=new Float32Array(16);
    for(let c=0;c<4;c++)for(let r=0;r<4;r++)for(let k=0;k<4;k++)out[c*4+r]+=a[k*4+r]*b[c*4+k];
    return out;
  }
export function projection(aspect){
    const f=1/Math.tan(.42), n=.1, z=20;
    return new Float32Array([f/aspect,0,0,0,0,f,0,0,0,0,(z+n)/(n-z),-1,0,0,2*z*n/(n-z),0]);
  }
export const eye=[0,1.45,3.3];
export const target=[0,.74,0];
export function viewMatrix(){
    const sub=(a,b)=>a.map((v,i)=>v-b[i]);
    const unit=a=>{const n=Math.hypot(...a);return a.map(v=>v/n);};
    const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
    const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
    const z=unit(sub(eye,target)),x=unit(cross([0,1,0],z)),y=cross(z,x);
    return new Float32Array([x[0],y[0],z[0],0,x[1],y[1],z[1],0,x[2],y[2],z[2],0,-dot(x,eye),-dot(y,eye),-dot(z,eye),1]);
  }
