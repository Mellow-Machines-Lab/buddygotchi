import {deformationGLSL} from '../engine/motion-v1.mjs';
import {matrixMultiply,projection,viewMatrix,eye} from './camera.mjs';
import {paintFace} from './face-painter.mjs';

// Supersampling tiers, as [factor, most scene pixels]. The body is drawn into
// an offscreen texture, where the context's antialias flag does nothing, so
// the scene is rendered at factor× the canvas in each dimension and averaged
// back down. Small canvases (the Mac popover's 46-pt face) get 4×, larger ones
// 2×, and past the budget the canvas's own dense pixels go unsupersampled.
const supersampleTiers=[[4,1024*1024],[2,4096*2048]];
export function sceneScale(width,height,maxSide=Infinity){
    for(const [factor,budget] of supersampleTiers)if(width*height*factor*factor<=budget&&Math.max(width,height)*factor<=maxSide)return factor;
    return 1;
  }

export function createWebGL(canvas, catalog){
    const faceCanvas=document.createElement('canvas');faceCanvas.width=512;faceCanvas.height=512;
    const faceContext=faceCanvas.getContext('2d');
    // Only the full-screen composite reaches the canvas, so it needs no
    // multisampling, and nothing reads it back, so it needn't be preserved.
    const gl=canvas.getContext('webgl',{alpha:true,antialias:false,premultipliedAlpha:false});
    if(!gl)throw new Error('WebGL unavailable');
    const vs=`
      precision highp float;
      attribute vec2 aParam;
      uniform mat4 uMatrix;
      uniform vec4 uModes;
      uniform vec2 uContact;
      uniform float uShell;
      uniform vec3 uGrab;
      uniform vec2 uGrabPoint;
      uniform vec3 uLife;
      varying vec3 vPosition;
      varying vec3 vNormal;
      varying vec3 vBase;
${deformationGLSL}
      // Local surface grab and emotion acting compose around the locked dome.
      vec3 extendedShape(vec2 uv){
        vec3 pos=shape(uv);
        vec2 rest=vec2(sin(uv.x)*cos(uv.y),cos(uv.x));
        float front=smoothstep(.05,.78,sin(uv.y));
        vec2 distanceToGrab=(rest-uGrabPoint)*vec2(1.8,1.65);
        float local=exp(-dot(distanceToGrab,distanceToGrab))*front;
        float h=clamp(pos.y/1.49,0.0,1.0);
        pos+=uGrab*(.78*local+.13*h*h);
        float y=pos.y-.62,x=pos.x,c=cos(uLife.y),s=sin(uLife.y);
        pos.x=x*c-y*s;pos.y=max(.018,x*s+y*c+.62+uLife.x);
        pos.z+=uLife.z*h*h;
        return pos;
      }
      void main(){
        vec3 pos=extendedShape(aParam);
        float t=aParam.x,p=aParam.y;
        vec3 dT=extendedShape(vec2(min(3.14149,t+.003),p))-extendedShape(vec2(max(.0001,t-.003),p));
        vec3 dP=extendedShape(vec2(t,p+.003))-extendedShape(vec2(t,p-.003));
        vec3 normal=cross(dP,dT);
        if(length(normal)<.000001)normal=vec3(0.0,cos(t)>0.0?1.0:-1.0,0.0);
        vNormal=normalize(normal);
        vPosition=pos;
        vBase=vec3(sin(t)*cos(p),cos(t),sin(t)*sin(p));
        vec3 shellPosition=(pos-vec3(0.0,.70,0.0))*uShell+vec3(0.0,.70,0.0);
        gl_Position=uMatrix*vec4(shellPosition,1.0);
      }
    `;
    const fs=`
      precision highp float;
      uniform vec3 uEye;
      uniform float uBlink;
      uniform float uGaze;
      uniform sampler2D uBackdrop;
      uniform vec2 uResolution;
      uniform sampler2D uFaceTexture;
      uniform float uTime;
      uniform vec4 uModes;
      varying vec3 vPosition;
      varying vec3 vNormal;
      varying vec3 vBase;
      float oval(vec2 q,vec2 radius){return 1.0-smoothstep(.92,1.06,length(q/radius));}
      float stroke(vec2 p,vec2 a,vec2 b,float width){
        vec2 d=b-a;
        float h=clamp(dot(p-a,d)/dot(d,d),0.0,1.0);
        return 1.0-smoothstep(width,width+.005,length(p-a-h*d));
      }
      // Capsule distances give every drawn line round ends and round joins.
      float happyEye(vec2 p){return max(stroke(p,vec2(-.072,.063),vec2(.056,0.0),.022),stroke(p,vec2(.056,0.0),vec2(-.072,-.048),.022));}
      float flatEye(vec2 p){return max(stroke(p,vec2(-.084,.023),vec2(.084,.023),.019),stroke(p,vec2(.010,.023),vec2(.010,-.047),.017));}
      float pointedEye(vec2 p){return stroke(p,vec2(-.065,.031),vec2(.049,-.016),.025);}
      float closedEye(vec2 p){
        float a=stroke(p,vec2(-.086,-.018),vec2(-.039,.029),.022);
        float b=stroke(p,vec2(-.039,.029),vec2(.017,.042),.022);
        return max(max(a,b),stroke(p,vec2(.017,.042),vec2(.082,.015),.022));
      }
      float wSmile(vec2 p){
        float a=max(stroke(p,vec2(-.093,-.128),vec2(-.060,-.158),.015),stroke(p,vec2(-.060,-.158),vec2(-.030,-.158),.015));
        a=max(a,stroke(p,vec2(-.030,-.158),vec2(0.0,-.130),.015));
        float b=max(stroke(p,vec2(0.0,-.130),vec2(.030,-.158),.015),stroke(p,vec2(.030,-.158),vec2(.060,-.158),.015));
        return max(max(a,b),stroke(p,vec2(.060,-.158),vec2(.093,-.128),.015));
      }
      void main(){
        vec3 N=normalize(vNormal),V=normalize(uEye-vPosition);
        vec3 L=normalize(vec3(-2.7,4.5,3.3)-vPosition);
        vec3 H=normalize(L+V);
        float nl=max(dot(N,L),0.0),nv=max(dot(N,V),0.0);
        // Screen-space transmission: the live studio and contact shadow are
        // sampled through a bent ray. Nothing here is a stored image asset.
        vec2 uv=gl_FragCoord.xy/uResolution;
        // Approximate a refracted chord through the persistent dome. Eight
        // samples integrate only smooth blue light: no inner cap or organs;
        // they are live shader functions, not textures or a video sequence.
        vec3 T=refract(-V,N,1.0/1.34);
        vec3 radii=vec3(1.10,.91,.847);
        vec3 q=(vPosition-vec3(0.0,.56,0.0))/radii, d=T/radii;
        float a=dot(d,d), b=dot(q,d), c=dot(q,q)-1.0;
        float disc=sqrt(max(b*b-a*c,0.0));
        float entry=max(0.0,(-b-disc)/a);
        float exit=max(entry,(-b+disc)/a);
        float thickness=min(exit-entry,2.4);
        vec2 bend=vec2(N.x,N.y*.78)*(.029+.040*thickness);
        vec2 refractedUV=clamp(uv-bend,vec2(.003),vec2(.997));
        vec3 backdrop=texture2D(uBackdrop,refractedUV).rgb;
        // Smooth, unfocused transmitted light inside one clear gel body.
        // No anatomical shapes, stripes, rings or separate inner object.
        float pulse=1.0+.03*sin(uTime*.95);
        vec3 throughput=vec3(1.0),volume=vec3(0.0);
        float stepLength=thickness/8.0;
        for(int i=0;i<8;i++){
          vec3 p=vPosition+T*(entry+stepLength*(float(i)+.5));
          // Keep the interior anchored to the same deforming body.
          p.y/=1.0+uModes.y*.52;
          float height=p.y/1.49;
          p.x=(p.x-uModes.x*.34*height*height)*sqrt(max(.76,1.0+uModes.y*.52));
          p.z=(p.z-uModes.x*.09*height)*sqrt(max(.76,1.0+uModes.y*.52));
          float inside=smoothstep(.028,.085,p.y);
          vec3 corePoint=(p-vec3(-.045,.46,-.08))*vec3(1.6,2.35,2.0);
          float core=exp(-dot(corePoint,corePoint)*1.7);
          vec3 lightPoint=(p-vec3(-.22,.83,-.09))*vec3(1.05,1.22,1.50);
          float softLight=exp(-dot(lightPoint,lightPoint)*1.25);
          float density=(.024+.025*core)*inside;
          vec3 emission=vec3(.040,.29,.85)*(.12+.20*core+.32*softLight);
          volume+=throughput*emission*stepLength*inside*pulse;
          throughput*=exp(-vec3(.52,.16,.035)*density*stepLength);
        }
        vec3 color=backdrop*throughput+volume;
        color+=vec3(.008,.055,.15)*nl*(.10+.09*thickness);
        vec3 R=reflect(-V,N);
        vec3 environment=mix(vec3(.08,.20,.44),vec3(.45,.80,1.0),smoothstep(-.20,.80,R.y));
        float fresnel=.020+.980*pow(1.0-nv,5.0);
        color=mix(color,environment,fresnel*.16);
        // Broad rectangular softboxes, plus a small crisp glint: wet jelly,
        // not a matte blue toy. Reflections move with the deforming normals.
        vec3 boxDirection=normalize(vec3(-.58,.80,.62));
        vec3 boxHorizontal=normalize(cross(boxDirection,vec3(0.0,1.0,0.0)));
        vec3 boxVertical=cross(boxHorizontal,boxDirection);
        float softbox=(1.0-smoothstep(.15,.24,abs(dot(R,boxHorizontal))))
                     *(1.0-smoothstep(.075,.14,abs(dot(R,boxVertical))))
                     *smoothstep(.80,.93,dot(R,boxDirection));
        float rimbox=pow(max(dot(R,normalize(vec3(.90,.38,-.24))),0.0),65.0);
        float spec=pow(max(dot(N,H),0.0),145.0);
        color+=vec3(.55,.84,1.0)*(softbox*.10+spec*.08);
        color+=vec3(.16,.61,1.0)*rimbox*.23;
        color+=vec3(.12,.52,1.10)*pow(1.0-nv,4.0)*.62;
        // Convert lit gel radiance for display before applying the crisp
        // graphic face. This avoids murky teal while keeping the ink dark.
        color=pow(vec3(1.0)-exp(-max(color,vec3(0.0))*1.25),vec3(.454545));
        float front=smoothstep(.59,.76,vBase.z);
        vec2 faceUV=(vBase.xy*.92+vec2(1.0))*.5;
        vec4 faceInk=texture2D(uFaceTexture,faceUV);
        color=mix(color,faceInk.rgb,faceInk.a*front);
        float alpha=.84+.13*pow(nv,.55);
        gl_FragColor=vec4(color,alpha);
      }
    `;
    function compile(type,source){const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(s));return s;}
    function program(vertex,fragment){const p=gl.createProgram();gl.attachShader(p,compile(gl.VERTEX_SHADER,vertex));gl.attachShader(p,compile(gl.FRAGMENT_SHADER,fragment));gl.linkProgram(p);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(p));return p;}
    const body=program(vs,fs);
    // The face is drawn many times smaller than its 512² canvas, so its
    // texture is mipmapped after every upload; sampled from the full-size
    // level alone, its strokes alias and shimmer as the body moves.
    const faceTexture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,faceTexture);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR_MIPMAP_LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,512,512,0,gl.RGBA,gl.UNSIGNED_BYTE,null);gl.generateMipmap(gl.TEXTURE_2D);
    const rings=42,sectors=72,params=[],indices=[];
    for(let y=0;y<=rings;y++)for(let x=0;x<=sectors;x++)params.push(Math.PI*(.00005+(1-.0001)*y/rings),Math.PI*2*x/sectors);
    for(let y=0;y<rings;y++)for(let x=0;x<sectors;x++){const a=y*(sectors+1)+x,b=a+sectors+1;indices.push(a,b,a+1,a+1,b,b+1);}
    const vertexBuffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,vertexBuffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(params),gl.STATIC_DRAW);
    const indexBuffer=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,new Uint16Array(indices),gl.STATIC_DRAW);
    const at=gl.getAttribLocation(body,'aParam');
    const uniforms={};for(const name of ['uMatrix','uModes','uContact','uEye','uBlink','uGaze','uBackdrop','uResolution','uFaceTexture','uTime','uShell','uGrab','uGrabPoint','uLife'])uniforms[name]=gl.getUniformLocation(body,name);
    const fullscreenVS=`attribute vec2 aPosition;varying vec2 vUV;void main(){vUV=aPosition*.5+.5;gl_Position=vec4(aPosition,0.0,1.0);}`;
    const studio=program(fullscreenVS,`precision highp float;void main(){gl_FragColor=vec4(0.0,0.0,0.0,1.0);}`);
    const screen=program(fullscreenVS,`precision highp float;varying vec2 vUV;uniform sampler2D uTexture;void main(){gl_FragColor=texture2D(uTexture,vUV);}`);
    const quad=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
    const studioAt=gl.getAttribLocation(studio,'aPosition'),screenAt=gl.getAttribLocation(screen,'aPosition');
    const screenTexture=gl.getUniformLocation(screen,'uTexture');
    // Quarter-resolution separable bloom spreads bright blue light into
    // the surrounding black. Unlike enlarged silhouette shells it cannot
    // produce concentric halo outlines or turn the whole body into a lamp.
    const blur=program(fullscreenVS,`precision highp float;varying vec2 vUV;uniform sampler2D uTexture;uniform vec2 uStep;uniform float uExtract;
      vec3 sampleLight(vec2 uv){vec3 c=texture2D(uTexture,uv).rgb;float brightness=max(c.r,max(c.g,c.b));return c*mix(1.0,smoothstep(.30,.78,brightness),uExtract);}
      void main(){vec3 c=sampleLight(vUV)*.227027;c+=(sampleLight(vUV+uStep*1.384615)+sampleLight(vUV-uStep*1.384615))*.316216;c+=(sampleLight(vUV+uStep*3.230769)+sampleLight(vUV-uStep*3.230769))*.070270;gl_FragColor=vec4(c,1.0);}`);
    const composite=program(fullscreenVS,`precision highp float;varying vec2 vUV;uniform sampler2D uScene;uniform sampler2D uBloom;void main(){vec3 c=texture2D(uScene,vUV).rgb;vec3 glow=texture2D(uBloom,vUV).rgb;gl_FragColor=vec4(min(c+glow*.50,vec3(1.0)),1.0);}`);
    // Averages each canvas pixel's block of the supersampled scene. A canvas
    // pixel's centre falls on a scene texel corner, so one bilinear tap there
    // is the mean of a 2×2 quad; four taps a quad's width apart cover 4×4.
    const resolve=program(fullscreenVS,`precision highp float;varying vec2 vUV;uniform sampler2D uTexture;uniform vec2 uOffset;void main(){vec2 o=uOffset;gl_FragColor=.25*(texture2D(uTexture,vUV-o)+texture2D(uTexture,vUV+vec2(o.x,-o.y))+texture2D(uTexture,vUV+vec2(-o.x,o.y))+texture2D(uTexture,vUV+o));}`);
    const blurAt=gl.getAttribLocation(blur,'aPosition'),compositeAt=gl.getAttribLocation(composite,'aPosition'),resolveAt=gl.getAttribLocation(resolve,'aPosition');
    const blurTexture=gl.getUniformLocation(blur,'uTexture'),blurStep=gl.getUniformLocation(blur,'uStep'),blurExtract=gl.getUniformLocation(blur,'uExtract');
    const compositeScene=gl.getUniformLocation(composite,'uScene'),compositeBloom=gl.getUniformLocation(composite,'uBloom');
    const resolveTexture=gl.getUniformLocation(resolve,'uTexture'),resolveOffset=gl.getUniformLocation(resolve,'uOffset');
    function newTarget(){
      const texture=gl.createTexture(),framebuffer=gl.createFramebuffer();
      gl.bindTexture(gl.TEXTURE_2D,texture);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      return {texture,framebuffer};
    }
    // sceneTarget holds the supersampled scene; resolved is it averaged down
    // to the canvas, which the bloom and composite read as before.
    const sceneTarget=newTarget(),resolved=newTarget(),bloomA=newTarget(),bloomB=newTarget(),sceneDepth=gl.createRenderbuffer();
    const viewportLimit=gl.getParameter(gl.MAX_VIEWPORT_DIMS);
    const maxSide=Math.min(gl.getParameter(gl.MAX_TEXTURE_SIZE),gl.getParameter(gl.MAX_RENDERBUFFER_SIZE),viewportLimit[0],viewportLimit[1]);
    function resizeTarget(target,w,h){
      gl.bindTexture(gl.TEXTURE_2D,target.texture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,w,h,0,gl.RGBA,gl.UNSIGNED_BYTE,null);
      gl.bindFramebuffer(gl.FRAMEBUFFER,target.framebuffer);
      // On viewport changes the old depth attachment temporarily has a
      // different size. Detach it until its matching allocation is ready.
      if(target===sceneTarget)gl.framebufferRenderbuffer(gl.FRAMEBUFFER,gl.DEPTH_ATTACHMENT,gl.RENDERBUFFER,null);
      gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,target.texture,0);
      if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)throw new Error('Bloom framebuffer unavailable');
    }
    const backdropTexture=gl.createTexture(),backdropTarget=gl.createFramebuffer();
    let targetWidth=0,targetHeight=0,scale=1,sceneWidth=0,sceneHeight=0;
    gl.bindTexture(gl.TEXTURE_2D,backdropTexture);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    const shadow=program(`attribute vec3 aPosition;uniform mat4 uMatrix;varying vec2 vXZ;void main(){vXZ=aPosition.xz;gl_Position=uMatrix*vec4(aPosition,1.0);}`,`precision highp float;varying vec2 vXZ;void main(){float d=dot(vXZ*vec2(.9,1.45),vXZ*vec2(.9,1.45));float a=.18*exp(-d*1.4)+.22*exp(-d*9.0);gl_FragColor=vec4(0.0,0.0,0.0,a);}`);
    const floor=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,floor);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-4,0,-4,4,0,-4,-4,0,4,-4,0,4,4,0,-4,4,0,4]),gl.STATIC_DRAW);
    const floorAt=gl.getAttribLocation(shadow,'aPosition');
    const floorMatrix=gl.getUniformLocation(shadow,'uMatrix');
    const camera=viewMatrix();
    const draw=(channels)=>{
      const {pose,life,contact,gaze,time,grab}=channels;
      gl.activeTexture(gl.TEXTURE0);
      if(targetWidth!==canvas.width||targetHeight!==canvas.height){
        targetWidth=canvas.width;targetHeight=canvas.height;
        scale=sceneScale(targetWidth,targetHeight,maxSide);sceneWidth=targetWidth*scale;sceneHeight=targetHeight*scale;
        gl.bindTexture(gl.TEXTURE_2D,backdropTexture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,targetWidth,targetHeight,0,gl.RGBA,gl.UNSIGNED_BYTE,null);
        gl.bindFramebuffer(gl.FRAMEBUFFER,backdropTarget);gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,backdropTexture,0);
        if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)throw new Error('Transmission framebuffer unavailable');
        resizeTarget(sceneTarget,sceneWidth,sceneHeight);
        gl.bindRenderbuffer(gl.RENDERBUFFER,sceneDepth);gl.renderbufferStorage(gl.RENDERBUFFER,gl.DEPTH_COMPONENT16,sceneWidth,sceneHeight);gl.framebufferRenderbuffer(gl.FRAMEBUFFER,gl.DEPTH_ATTACHMENT,gl.RENDERBUFFER,sceneDepth);
        if(scale>1)resizeTarget(resolved,targetWidth,targetHeight);
        resizeTarget(bloomA,Math.max(1,Math.ceil(targetWidth/4)),Math.max(1,Math.ceil(targetHeight/4)));
        resizeTarget(bloomB,Math.max(1,Math.ceil(targetWidth/4)),Math.max(1,Math.ceil(targetHeight/4)));
      }
      gl.bindFramebuffer(gl.FRAMEBUFFER,backdropTarget);
      gl.viewport(0,0,canvas.width,canvas.height);gl.disable(gl.BLEND);gl.disable(gl.DEPTH_TEST);
      gl.useProgram(studio);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(studioAt);gl.vertexAttribPointer(studioAt,2,gl.FLOAT,false,0,0);gl.drawArrays(gl.TRIANGLES,0,3);
      const matrix=matrixMultiply(projection(canvas.width/canvas.height),camera);
      gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.disable(gl.DEPTH_TEST);
      gl.useProgram(shadow);gl.uniformMatrix4fv(floorMatrix,false,matrix);gl.bindBuffer(gl.ARRAY_BUFFER,floor);gl.enableVertexAttribArray(floorAt);gl.vertexAttribPointer(floorAt,3,gl.FLOAT,false,0,0);gl.drawArrays(gl.TRIANGLES,0,6);
      gl.bindFramebuffer(gl.FRAMEBUFFER,sceneTarget.framebuffer);gl.viewport(0,0,sceneWidth,sceneHeight);gl.clearColor(0,0,0,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
      gl.disable(gl.BLEND);gl.useProgram(screen);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(screenAt);gl.vertexAttribPointer(screenAt,2,gl.FLOAT,false,0,0);
      gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,backdropTexture);gl.uniform1i(screenTexture,0);gl.drawArrays(gl.TRIANGLES,0,3);
      gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.enable(gl.CULL_FACE);gl.frontFace(gl.CW);gl.cullFace(gl.BACK);
      gl.useProgram(body);gl.bindBuffer(gl.ARRAY_BUFFER,vertexBuffer);gl.enableVertexAttribArray(at);gl.vertexAttribPointer(at,2,gl.FLOAT,false,0,0);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer);
      gl.uniformMatrix4fv(uniforms.uMatrix,false,matrix);gl.uniform4fv(uniforms.uModes,pose);gl.uniform2f(uniforms.uContact,contact.x,contact.y);gl.uniform3fv(uniforms.uEye,eye);gl.uniform1f(uniforms.uBlink,channels.face.blink);gl.uniform1f(uniforms.uGaze,gaze);
      gl.uniform1i(uniforms.uBackdrop,0);gl.uniform2f(uniforms.uResolution,sceneWidth,sceneHeight);paintFace(faceContext,channels,catalog);gl.activeTexture(gl.TEXTURE2);gl.bindTexture(gl.TEXTURE_2D,faceTexture);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,true);gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,gl.RGBA,gl.UNSIGNED_BYTE,faceCanvas);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);gl.generateMipmap(gl.TEXTURE_2D);gl.uniform1i(uniforms.uFaceTexture,2);gl.activeTexture(gl.TEXTURE0);
      gl.uniform3fv(uniforms.uGrab,grab.pull);gl.uniform2fv(uniforms.uGrabPoint,grab.point);gl.uniform3fv(uniforms.uLife,life);gl.uniform1f(uniforms.uTime,channels.reducedMotion?0:time);gl.uniform1f(uniforms.uShell,1);
      gl.drawElements(gl.TRIANGLES,indices.length,gl.UNSIGNED_SHORT,0);
      gl.disable(gl.CULL_FACE);gl.disable(gl.DEPTH_TEST);gl.disable(gl.BLEND);
      // Average the scene down to the canvas; the bloom and composite then
      // read a canvas-sized image exactly as they would without supersampling.
      if(scale>1){
        gl.bindFramebuffer(gl.FRAMEBUFFER,resolved.framebuffer);gl.viewport(0,0,canvas.width,canvas.height);
        gl.useProgram(resolve);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(resolveAt);gl.vertexAttribPointer(resolveAt,2,gl.FLOAT,false,0,0);
        gl.bindTexture(gl.TEXTURE_2D,sceneTarget.texture);gl.uniform1i(resolveTexture,0);gl.uniform2f(resolveOffset,(scale-2)/2/sceneWidth,(scale-2)/2/sceneHeight);gl.drawArrays(gl.TRIANGLES,0,3);
      }
      const shown=scale>1?resolved:sceneTarget;
      const bloomWidth=Math.max(1,Math.ceil(canvas.width/4)),bloomHeight=Math.max(1,Math.ceil(canvas.height/4));
      gl.bindFramebuffer(gl.FRAMEBUFFER,bloomA.framebuffer);gl.viewport(0,0,bloomWidth,bloomHeight);
      gl.useProgram(blur);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(blurAt);gl.vertexAttribPointer(blurAt,2,gl.FLOAT,false,0,0);
      gl.bindTexture(gl.TEXTURE_2D,shown.texture);gl.uniform1i(blurTexture,0);gl.uniform2f(blurStep,1.4/bloomWidth,0);gl.uniform1f(blurExtract,1);gl.drawArrays(gl.TRIANGLES,0,3);
      gl.bindFramebuffer(gl.FRAMEBUFFER,bloomB.framebuffer);gl.bindTexture(gl.TEXTURE_2D,bloomA.texture);gl.uniform2f(blurStep,0,1.4/bloomHeight);gl.uniform1f(blurExtract,0);gl.drawArrays(gl.TRIANGLES,0,3);
      gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.viewport(0,0,canvas.width,canvas.height);
      gl.useProgram(composite);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(compositeAt);gl.vertexAttribPointer(compositeAt,2,gl.FLOAT,false,0,0);
      gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,shown.texture);gl.uniform1i(compositeScene,0);gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,bloomB.texture);gl.uniform1i(compositeBloom,1);gl.drawArrays(gl.TRIANGLES,0,3);gl.activeTexture(gl.TEXTURE0);
    };
    return {draw,canvas,kind:'procedural-webgl'};
  }
