// The face painter: each expression's art as the Canvas calls that draw it
// at rest, eyes, mouth, cheeks, tears and all. art.mjs captures the calls
// as vector paths into slime_art.h, and the board draws those, moved and
// sized by its controls.
export function paintArt(ctx, profile, face){
    const unit=256*1.24;
    ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,512,512);
    ctx.setTransform(256,0,0,-256,256,256);ctx.scale(1.24,1.24);
    const ink='#0d2b48',water='#c5edf5';
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
    // A dark eye under a lid: what's below the lid's line `top` (above
    // `bottom`, when given) shows, the lid tilted by `tilt`.
    function lidded(rx,ry,top,bottom,tilt=0){
      ctx.save();ctx.beginPath();
      const low=bottom===undefined?-ry-.02:bottom;
      ctx.moveTo(-rx-.02,low);ctx.lineTo(rx+.02,low);ctx.lineTo(rx+.02,top+tilt*(rx+.02));ctx.lineTo(-rx-.02,top-tilt*(rx+.02));ctx.closePath();
      ctx.clip();egg(0,0,rx,ry,ink);ctx.restore();
    }
    function eyeArc(width=.128,height=.092,weight=.031){q([-width,-.018],[0,height],[width,-.018],weight);}
    function droop(width=.128,depth=.069,weight=.030){q([-width,.030],[-.014,-depth],[width,.017],weight);}
    function squeeze(width=.109,weight=.030){
      c([-width,.049],[-.035,.042],[.020,.014],[.067,-.004],weight);
      c([.067,-.004],[.015,-.008],[-.040,-.030],[-width,-.055],weight);
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
      else if(kind==='baby-w')wSmile(.076,.037,.023);
      else if(kind==='baby-yawn')egg(0,-.015,.036,.049,ink);
      else if(kind==='happy-u')roundedOpen(.076,.121,{pale:true});
      else if(kind==='wide-laugh')roundedOpen(.135,.107,{tilt:-.075,tongue:true});
      else if(kind==='crooked-grin')roundedOpen(.086,.060,{tilt:-.19,tongue:true});
      else if(kind==='small-u-line')q([-.044,.012],[0,-.029],[.044,.012],.022);
      else if(kind==='firm-w')wSmile(.062,.024,.024,.007);
      else if(kind==='curled-smirk'){wSmile(.075,.032,.024,.030);q([.074,.041],[.090,.054],[.096,.071],.018);}
      else if(kind==='puckered-three'){
        c([-.033,.053],[.061,.064],[.074,.008],[.006,.005],.024);
        c([.006,.005],[.076,.006],[.059,-.060],[-.032,-.048],.024);
      }
      else if(kind==='warm-w')wSmile(.068,.036,.023);
      else if(kind==='small-pout')q([-.032,-.010],[0,.030],[.032,-.010],.023);
      else if(kind==='pushed-pout')q([-.036,.006],[.026,.011],[.043,-.021],.025);
      else if(kind==='grumpy-pout'){
        q([-.065,-.020],[-.028,.039],[0,.010],.025);
        q([0,.010],[.029,.039],[.065,-.020],.025);
      }
      else if(kind==='protest-bean')roundedOpen(.074,.075,{tongue:true});
      else if(kind==='sad-pout')q([-.035,-.015],[0,.028],[.035,-.015],.022);
      else if(kind==='hurt-pout')q([-.033,-.013],[0,.033],[.033,-.013],.022);
      else if(kind==='round-gasp')egg(0,-.008,.035,.047,ink);
      // Curious's: a small open o, tilted toward what it peers at.
      else if(kind==='peering-o')egg(0,0,.024,.034,'rgba(153,216,236,.75)',.30,.017);
      // The meme faces': deadpan's dead flat line, side-eye's short one
      // aslant, the squint's and the faint's wobble, smug's cat w, and the
      // silent scream's tall open oval.
      else if(kind==='flat-line')stroke([['M',-.050,0],['L',.050,0]],.024);
      else if(kind==='side-line')stroke([['M',-.010,.004],['L',.058,-.008]],.024);
      else if(kind==='wavy-line')stroke([['M',-.060,0],['C',-.040,.026,-.020,-.026,0,0],['C',.020,.026,.040,-.026,.060,0]],.022);
      else if(kind==='cat-w')wSmile(.074,.044,.024,.010);
      else if(kind==='scream-o'){egg(0,-.050,.068,.112,ink);egg(0,-.120,.034,.026,'#afdde8');}
    }
    // The features, each drawn by its own function: the cheeks, the tears,
    // each eye, the strain mark and the mouth.
    const p=profile,a={...p.art,eyeX:face.eyeX,eyeY:face.eyeY,mouthY:face.mouthY};
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
        const x=side*a.eyeX,start=a.eyeY-.040,end=-.42;
        const width=p.tears==='thin'?.021:.019;
        const strength=p.tears==='occasional'?.30:1;
        ctx.save();ctx.globalAlpha*=strength*face.tearAmount;
        const fill=ctx.createLinearGradient(x,start,x,end);
        fill.addColorStop(0,'rgba(173,225,243,.55)');fill.addColorStop(.65,'rgba(117,201,235,.41)');fill.addColorStop(1,'rgba(98,181,224,.06)');
        ctx.beginPath();ctx.moveTo(x-width,start);
        ctx.bezierCurveTo(x-width,-.12,x-width,-.28,x-width*.82,end+.045);
        ctx.quadraticCurveTo(x-width*.5,end-.02,x,end);
        ctx.quadraticCurveTo(x+width*.6,end-.02,x+width*.8,end+.045);
        ctx.bezierCurveTo(x+width,-.28,x+width,-.12,x+width,start);ctx.closePath();
        ctx.fillStyle=fill;ctx.fill();
        q([x-width*.52,start-.013],[x-width*.7,-.10],[x-width*.42,-.18],.006,'rgba(215,245,253,.35)');
        q([x+width*.5,-.24],[x+width*.3,-.29],[x+width*.5,-.34],.006,'rgba(206,239,251,.27)');
        ctx.restore();
      }
    }};
    const eye=side=>{
      ctx.save();ctx.translate(side*a.eyeX,a.eyeY);
      ctx.scale(side===1?-1:1,1);
      const type=a.eyes;
      if(type==='soft-dot')bean(.035,.049);
      else if(type==='sleepy-lid')droop(.112,.041,.030);
      else if(type==='pleased-bean')bean(.073,.022,-.43);
      else if(type==='happy-dot')bean(.043,.046);
      else if(type==='laugh-lid')eyeArc(.128,.123,.033);
      else if(type==='amused-wink'){if(side===-1)eyeArc(.112,.083,.032);else bean(.045,.053);}
      // Curious peers: one eye clearly bigger and higher under a lifted
      // brow, the other small, so it reads apart from calm across a desk.
      else if(type==='curious-eggs'){
        if(side===1){ctx.translate(0,.014);bean(.050,.068,-.06);q([-.064,.112],[.006,.142],[.070,.118],.019);}
        else{ctx.translate(0,-.010);bean(.031,.043);}
      }
      else if(type==='attentive-eggs')bean(.034,.058);
      else if(type==='gentle-resolve'){bean(.035,.056);q([-.070,.103],[.008,.117],[.062,.133],.020);}
      else if(type==='smug-lids'){bean(.070,.018,.23);q([-.065,.003],[.013,-.024],[.073,.019],.021);}
      else if(type==='cheeky-beans')bean(.054,.018,-.49);
      else if(type==='warm-lids')eyeArc(.118,.087,.030);
      else if(type==='longing-beans'){bean(.029,.043,-.16);q([-.052,.099],[.010,.103],[.058,.130],.018);}
      else if(type==='annoyed-beans')bean(side===-1?.071:.054,side===-1?.024:.030,side===-1?.07:-.05);
      else if(type==='grumpy-beans')bean(.088,.026,-.39);
      else if(type==='angry-squeeze')squeeze(.115,.032);
      else if(type==='sad-lids')droop(.128,.077,.029);
      else if(type==='hurt-eggs')bean(.024,.050);
      else if(type==='surprise-dots')bean(.043,.058);
      // The meme faces': solid dark eyes still, the lids and where they
      // look doing the acting. Deadpan's under flat lids half down;
      // side-eye's a flat lid's line across, the eye pressed under its one
      // end, both to your right; squint's one eye narrowed to a slit, the
      // other under a flat lid; smug's half under a tilted lid, glancing
      // aside; the scream's tall; the faint's crosses.
      else if(type==='flat-lids')lidded(.044,.058,.008);
      else if(type==='side-glance'){stroke([['M',-.066,.012],['L',.066,.012]],.024);ctx.translate(-side*.034,0);lidded(.034,.046,.012);}
      else if(type==='slits'){if(side===-1){ctx.rotate(-.10);lidded(.064,.046,.014,-.014);}else lidded(.042,.056,.016);}
      else if(type==='smug-half'){ctx.translate(-side*.012,0);lidded(.046,.052,.010,undefined,-.16);}
      else if(type==='scream-eggs')bean(.044,.074);
      else if(type==='x-eyes')stroke([['M',-.038,.038],['L',.038,-.038],['M',-.038,-.038],['L',.038,.038]],.026);
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
