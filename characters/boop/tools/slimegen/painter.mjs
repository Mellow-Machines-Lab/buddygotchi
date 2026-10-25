// The face painter: each expression's art as the Canvas calls that draw it
// at rest, eyes, mouth, cheeks, tears and all. art.mjs captures the calls
// as vector paths into slime_art.h, and the board draws those, moved and
// sized by its controls.
export function paintArt(ctx, profile, face){
    const unit=256*1.24;
    ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,512,512);
    ctx.setTransform(256,0,0,-256,256,256);ctx.scale(1.24,1.24);
    const ink='#0d2b48',water='#c5edf5',tearInk='#70b8d4';
    // Paths take the feature's scale; the pen keeps its authored width, so a
    // squashed or stretched feature never thins or thickens its lines.
    function pen(){ctx.save();ctx.setTransform(unit,0,0,-unit,256,256);ctx.stroke();ctx.restore();}
    function stroke(commands,width=.027,color=ink){
      ctx.beginPath();ctx.strokeStyle=color;ctx.lineWidth=width;ctx.lineCap='round';ctx.lineJoin='round';
      for(const [kind,...v] of commands){
        if(kind==='M')ctx.moveTo(...v);else if(kind==='L')ctx.lineTo(...v);else if(kind==='Q')ctx.quadraticCurveTo(...v);else if(kind==='C')ctx.bezierCurveTo(...v);
      }pen();
    }
    const q=(a,b,c,width=.027,color=ink)=>stroke([['M',...a],['Q',...b,...c]],width,color);
    const c=(a,b,d,e,width=.027,color=ink)=>stroke([['M',...a],['C',...b,...d,...e]],width,color);
    function egg(x,y,rx,ry,fill=ink,angle=0,edge=0){
      ctx.save();ctx.translate(x,y);ctx.rotate(angle);ctx.beginPath();ctx.ellipse(0,0,rx,ry,0,0,Math.PI*2);
      ctx.fillStyle=fill;ctx.fill();if(edge){ctx.strokeStyle=ink;ctx.lineWidth=edge;pen();}ctx.restore();
    }
    function bean(rx,ry,angle=0){egg(0,0,rx,ry,ink,angle);}
    function eyeArc(width=.128,height=.092,weight=.031){q([-width,-.018],[0,height],[width,-.018],weight);}
    function droop(width=.128,depth=.069,weight=.030){q([-width,.030],[-.014,-depth],[width,.017],weight);}
    function squeeze(width=.109,weight=.030){
      c([-width,.049],[-.035,.042],[.020,.014],[.067,-.004],weight);
      c([.067,-.004],[.015,-.008],[-.040,-.030],[-width,-.055],weight);
    }
    function softWaterEye(rx,ry,angle=0){
      egg(0,0,rx,ry,water,angle,.016);
      ctx.save();ctx.rotate(angle);q([-rx*.65,-ry*.6],[0,-ry*.94],[rx*.7,-ry*.48],.008,'rgba(113,178,206,.55)');ctx.restore();
    }
    // A wide, dark frightened eye with a tear welling over its lower half:
    // one smooth see-through pool with a bright brim and a glint, the eye
    // showing above it and through it (the owner's 2026-10-05 redraw of the
    // puffy clouds, which read as cotton at the device's size).
    function wellingEye(){
      bean(.052,.068);
      egg(-.017,.030,.014,.017,'#eaf8fc');
      ctx.beginPath();ctx.moveTo(-.090,-.010);
      ctx.quadraticCurveTo(0,.016,.090,-.010);
      ctx.bezierCurveTo(.094,-.066,-.094,-.066,-.090,-.010);
      ctx.closePath();ctx.fillStyle='rgba(197,237,245,.55)';ctx.fill();
      q([-.076,-.005],[0,.017],[.076,-.005],.009,'rgba(236,250,255,.85)');
      egg(.044,-.030,.011,.008,'rgba(255,255,255,.8)');
    }
    function wSmile(width=.076,height=.038,weight=.023,smirk=0){
      q([-width,.014],[-width*.51,-height],[0,.017],weight);
      q([0,.017],[width*.47,-height*.94],[width,.014+smirk],weight);
    }
    function roundedOpen(width,depth,{pale=false,tilt=0,tongue=false}={}){
      ctx.save();ctx.rotate(tilt);ctx.beginPath();ctx.moveTo(-width,.040);
      ctx.quadraticCurveTo(0,.054,width,.040);
      ctx.bezierCurveTo(width*.95,-depth,width*.40,-depth,0,-depth);
      ctx.bezierCurveTo(-width*.40,-depth,-width*.95,-depth,-width,.040);ctx.closePath();
      ctx.fillStyle=pale?water:ink;ctx.fill();ctx.strokeStyle=ink;ctx.lineWidth=.022;ctx.lineJoin='round';pen();
      if(tongue){ctx.save();ctx.clip();egg(width*.06,-depth+.025,width*.71,.036,'#afdde8');ctx.restore();}
      ctx.restore();
    }
    function littleMouth(kind){
      if(kind==='tiny-ring')egg(0,0,.018,.026,'rgba(153,216,236,.6)',0,.014);
      else if(kind==='little-bean')roundedOpen(.046,.061,{tongue:true});
      else if(kind==='baby-w')wSmile(.076,.037,.023);
      else if(kind==='tiny-frown')q([-.031,-.010],[0,.031],[.031,-.010],.021);
      else if(kind==='baby-yawn')egg(0,-.015,.036,.049,ink);
      else if(kind==='spent-pout')q([-.046,.005],[0,-.006],[.040,-.009],.023);
      else if(kind==='happy-u')roundedOpen(.076,.121,{pale:true});
      else if(kind==='wide-laugh')roundedOpen(.135,.107,{tilt:-.075,tongue:true});
      else if(kind==='crooked-grin')roundedOpen(.086,.060,{tilt:-.19,tongue:true});
      else if(kind==='small-u-line')q([-.044,.012],[0,-.029],[.044,.012],.022);
      else if(kind==='firm-w')wSmile(.062,.024,.024,.007);
      else if(kind==='tilted-o')egg(0,0,.020,.031,water,.23,.017);
      else if(kind==='little-triangle'||kind==='shook-triangle'||kind==='tiny-triangle'){
        const width=kind==='tiny-triangle'?.031:.037;
        stroke([['M',-width,.014],['Q',0,.022,width,.014],['Q',width*.7,-.024,0,-.037],['Q',-width*.7,-.024,-width,.014]],.019);
      }
      else if(kind==='crooked-pout')q([-.043,-.003],[.010,.020],[.042,-.017],.023);
      else if(kind==='curled-smirk'){wSmile(.075,.032,.024,.030);q([.074,.041],[.090,.054],[.096,.071],.018);}
      else if(kind==='puckered-three'){
        c([-.033,.053],[.061,.064],[.074,.008],[.006,.005],.024);
        c([.006,.005],[.076,.006],[.059,-.060],[-.032,-.048],.024);
      }
      else if(kind==='tiny-v')q([-.028,.014],[0,-.048],[.028,.014],.021);
      else if(kind==='awkward-w'){ctx.rotate(.10);wSmile(.058,.031,.022,.008);}
      else if(kind==='warm-w')wSmile(.068,.036,.023);
      else if(kind==='small-pout')q([-.032,-.010],[0,.030],[.032,-.010],.023);
      else if(kind==='pushed-pout')q([-.036,.006],[.026,.011],[.043,-.021],.025);
      else if(kind==='tense-pout'){q([-.052,-.012],[0,.034],[.047,-.009],.023);}
      else if(kind==='grumpy-pout'){
        q([-.065,-.020],[-.028,.039],[0,.010],.025);
        q([0,.010],[.029,.039],[.065,-.020],.025);
      }
      else if(kind==='protest-bean')roundedOpen(.074,.075,{tongue:true});
      else if(kind==='sad-pout')q([-.035,-.015],[0,.028],[.035,-.015],.022);
      else if(kind==='quivering-pout'){
        q([-.047,-.014],[-.020,.031],[0,.007],.023);
        q([0,.007],[.021,.031],[.047,-.014],.023);
      }
      else if(kind==='complaining-pout'){
        ctx.beginPath();ctx.moveTo(-.062,-.010);ctx.quadraticCurveTo(-.034,.047,0,.023);
        ctx.quadraticCurveTo(.035,.047,.061,-.010);ctx.quadraticCurveTo(0,-.052,-.062,-.010);
        ctx.fillStyle=ink;ctx.fill();ctx.save();ctx.clip();egg(0,-.036,.040,.025,'#afdde8');ctx.restore();
      }
      else if(kind==='hurt-pout')q([-.033,-.013],[0,.033],[.033,-.013],.022);
      else if(kind==='uneasy-wave'||kind==='fear-wave'||kind==='small-waver'){
        const width=kind==='fear-wave'?.079:kind==='small-waver'?.062:.058;
        const height=kind==='fear-wave'?.032:.024;
        stroke([['M',-width,-.006],['Q',-width*.72,height,-width*.36,.002],['Q',0,-height*.62,width*.34,.004],['Q',width*.71,height,width,-.006]],.023);
      }
      else if(kind==='frightened-pout'){
        c([-.070,-.026],[-.045,.081],[.046,.081],[.070,-.026],.024);
        q([-.021,.009],[-.008,-.010],[-.009,-.019],.015);
        q([.021,.009],[.008,-.010],[.009,-.019],.015);
      }
      else if(kind==='round-gasp')egg(0,-.008,.035,.047,ink);
      else if(kind==='tiny-caret')q([-.030,-.013],[0,.030],[.030,-.013],.021);
      else if(kind==='exhale-bean')roundedOpen(.048,.050,{tongue:true});
      else if(kind==='side-blep'){
        q([-.053,.004],[.009,.035],[.051,-.013],.023);
        q([.019,-.008],[.021,-.036],[.039,-.026],.017,'#a9d5df');
      }
      else if(kind==='blank-line')q([-.041,0],[0,-.002],[.041,0],.022);
    }
    // The features, each drawn by its own function: the cheeks, the tears,
    // each eye, the strain mark and the mouth.
    const p=profile,a={...p.art,eyeX:face.eyeX,eyeY:face.eyeY,mouthY:face.mouthY},mood=p.mood;
    const glance=mood==='embarrassed'?-.019:0;
    // Graphic oval cheeks, not barely visible glossy shader freckles.
    const cheeks=()=>{if(a.cheeks!=='none'){
      const alpha=ctx.globalAlpha;
      const rosy=a.cheeks==='blush',hatch=a.cheeks==='hatch',soft=a.cheeks==='soft';
      const opacity=(rosy?.42:hatch?.31:soft?.18:a.cheeks==='freckles'?.22:.12)*face.cheekAlpha;
      for(const side of [-1,1]){
        ctx.globalAlpha=alpha*opacity;
        egg(side*.435,-.053,rosy?.101:.080,rosy?.041:.032,'#f0a5bb',-.08*side);
        if(rosy||hatch){ctx.globalAlpha=alpha*face.cheekAlpha*(rosy?.45:.28);for(let j=-1;j<=1;j++)q([side*.435+j*.026-.007,-.039],[side*.435+j*.026,-.054],[side*.435+j*.026+.007,-.073],.012,'#bc7895');}
        if(a.cheeks==='freckles'){ctx.globalAlpha=alpha*face.cheekAlpha*.40;for(const [x,y,r] of [[.46,-.087,.010],[.49,-.063,.011],[.43,-.100,.007]])egg(side*x,y,r,r,'#508caf');}
        if(a.cheeks==='strain'||a.cheeks==='effort'){ctx.globalAlpha=alpha*face.cheekAlpha*.30;q([side*.437-.02,-.047],[side*.437-.01,-.061],[side*.437,-.075],.011);}
      }
      ctx.globalAlpha=alpha;
    }};
    // Tears are individually shaped to the eyes and are drawn behind lids.
    const tears=()=>{if(p.tears!=='none'&&face.tearAmount>0){
      for(const side of [-1,1]){
        const x=side*a.eyeX,start=a.eyeY-(mood==='frightened'?.027:mood==='crying'?.005:.040);
        const broad=p.tears==='sheets',thin=p.tears==='thin';
        const width=broad?(mood==='frightened'?.090:.078):thin?.021:.019;
        const strength=p.tears==='occasional'?.30:1;
        ctx.save();ctx.globalAlpha*=strength*face.tearAmount;
        if(broad||thin||p.tears==='occasional'){
          const end=broad?-.49:-.42,wave=0;
          const fill=ctx.createLinearGradient(x,start,x,end);
          fill.addColorStop(0,'rgba(173,225,243,.55)');fill.addColorStop(.65,'rgba(117,201,235,.41)');fill.addColorStop(1,'rgba(98,181,224,.06)');
          ctx.beginPath();ctx.moveTo(x-width,start);
          ctx.bezierCurveTo(x-width-wave,-.12,x-width+wave,-.28,x-width*.82,end+.045);
          ctx.quadraticCurveTo(x-width*.5,end-.02,x,end);
          ctx.quadraticCurveTo(x+width*.6,end-.02,x+width*.8,end+.045);
          ctx.bezierCurveTo(x+width+wave,-.28,x+width-wave,-.12,x+width,start);ctx.closePath();
          ctx.fillStyle=fill;ctx.fill();
          q([x-width*.52,start-.013],[x-width*.7+wave,-.10],[x-width*.42,-.18],broad?.009:.006,'rgba(215,245,253,.35)');
          q([x+width*.5,-.24],[x+width*.3-wave,-.29],[x+width*.5,-.34],broad?.009:.006,'rgba(206,239,251,.27)');
        }else{
          egg(x-side*.054,a.eyeY-.061,.031,.023,water,0,.009);
        }ctx.restore();
      }
    }};
    const eye=side=>{
      ctx.save();ctx.translate(side*a.eyeX+glance,a.eyeY);
      ctx.scale(side===1?-1:1,1);
      const type=a.eyes;
      if(type==='soft-dot')bean(.035,.049);
      else if(type==='comfy-dash')bean(.042,.014,-.035);
      else if(type==='lazy-equals'){q([-.100,.028],[0,.034],[.100,.024],.023);q([-.100,-.014],[0,-.009],[.100,-.016],.023);}
      else if(type==='bored-bean')bean(.066,.026,.055);
      else if(type==='sleepy-lid')droop(.112,.041,.030);
      else if(type==='spent-lid')droop(.140,.090,.032);
      else if(type==='pleased-bean')bean(.073,.022,-.43);
      else if(type==='happy-dot')bean(.043,.046);
      else if(type==='laugh-lid')eyeArc(.128,.123,.033);
      else if(type==='amused-wink'){if(side===-1)eyeArc(.112,.083,.032);else bean(.045,.053);}
      else if(type==='curious-eggs')bean(.037,.049);
      else if(type==='attentive-eggs')bean(.034,.058);
      else if(type==='gentle-resolve'){bean(.035,.056);q([-.070,.103],[.008,.117],[.062,.133],.020);}
      else if(type==='puzzled-eggs'){bean(side===-1?.026:.042,side===-1?.046:.065);if(side===-1)q([-.051,.102],[.005,.137],[.064,.128],.019);}
      else if(type==='baffled-eggs'){bean(side===-1?.045:.029,side===-1?.073:.042);if(side===1)q([-.043,.108],[.003,.112],[.053,.087],.018);}
      else if(type==='skeptical-lids'){
        if(side===-1){q([-.115,.028],[0,.023],[.098,-.007],.029);bean(.036,.015,.0);}
        else bean(.063,.026,-.25);
      }
      else if(type==='smug-lids'){bean(.070,.018,.23);q([-.065,.003],[.013,-.024],[.073,.019],.021);}
      else if(type==='cheeky-beans')bean(.054,.018,-.49);
      else if(type==='bashful-squeeze'){c([-.090,.037],[-.040,.032],[.015,.000],[.049,-.019],.027);c([.049,-.019],[.006,-.018],[-.040,-.031],[-.076,-.039],.026);}
      else if(type==='averted-eggs')bean(.026,.045,.11);
      else if(type==='warm-lids')eyeArc(.118,.087,.030);
      else if(type==='longing-beans'){bean(.029,.043,-.16);q([-.052,.099],[.010,.103],[.058,.130],.018);}
      else if(type==='annoyed-beans')bean(side===-1?.071:.054,side===-1?.024:.030,side===-1?.07:-.05);
      else if(type==='irritated-beans')bean(.072,.023,-.22);
      else if(type==='grumpy-beans')bean(.088,.026,-.39);
      else if(type==='angry-squeeze')squeeze(.115,.032);
      else if(type==='letdown-lids')droop(.097,.035,.029);
      else if(type==='sad-lids')droop(.128,.077,.029);
      else if(type==='crying-lids')droop(.139,.091,.032);
      else if(type==='pleading-eyes'){bean(.044,.059,-.18);q([-.058,.112],[.008,.108],[.074,.152],.021);q([-.051,-.047],[0,-.075],[.047,-.040],.017,tearInk);}
      else if(type==='hurt-eggs')bean(.024,.050);
      else if(type==='cautious-eggs'){bean(.030,.050,side===-1?-.10:.07);if(side===-1)q([-.040,.101],[.006,.119],[.050,.110],.016);}
      else if(type==='scared-water'){softWaterEye(.084,.080);egg(-.091,-.045,.033,.023,water,0,.014);}
      else if(type==='welling-eyes')wellingEye();
      else if(type==='surprise-dots')bean(.043,.058);
      else if(type==='shook-ovals')softWaterEye(.045,.029,-.03);
      else if(type==='stare-lids'){q([-.118,.027],[0,.014],[.112,.013],.032);q([.005,.010],[.001,-.008],[.004,-.038],.025);}
      else if(type==='hopeful-eggs')bean(.037,.060,-.09);
      else if(type==='released-lids')eyeArc(.128,.089,.029);
      else if(type==='uneasy-almonds')softWaterEye(.080,.050,-.26);
      else if(type==='wince-lids')squeeze(.094,.028);
      else if(type==='overloaded-eggs'){bean(side===-1?.039:.028,side===-1?.069:.051);q([-.049,.108],[.001,.110],[.049,.091],.017);}
      else if(type==='rosy-beans')bean(.041,.016,-.18);
      else if(type==='blank-water')softWaterEye(.039,.019);
      ctx.restore();
    };
    const strain=()=>{if(a.cheeks==='strain'){
      const alpha=ctx.globalAlpha;ctx.globalAlpha=alpha*face.cheekAlpha*.35;
      q([-.015,.200],[-.002,.208],[.013,.200],.012);ctx.globalAlpha=alpha;
    }};
    const mouth=()=>{
      ctx.save();ctx.translate(0,a.mouthY);
      littleMouth(a.mouth);ctx.restore();
    };
    ctx.save();ctx.globalAlpha=1;
    for(const feature of [cheeks,tears,()=>eye(-1),()=>eye(1),strain,mouth])feature();
    ctx.restore();
    ctx.setTransform(1,0,0,1,0,0);
  }
