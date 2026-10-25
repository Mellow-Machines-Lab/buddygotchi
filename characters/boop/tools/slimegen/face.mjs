// Each expression's face as the board's controls: where its eyes and mouth
// sit, and the sizes its art draws them at, which the board's springs move
// between and its drawn ratios are over. The sizes are read off the face
// painter's art primitives (painter.mjs): at rest each ratio is one,
// preserving the authored face.
const eyeDimensions={
  'soft-dot':.049,'comfy-dash':.014,'lazy-equals':.025,'bored-bean':.026,
  'sleepy-lid':.041,'spent-lid':.090,'pleased-bean':.022,'happy-dot':.046,
  'laugh-lid':.123,'amused-wink':.068,'curious-eggs':.049,'attentive-eggs':.058,
  'gentle-resolve':.056,'puzzled-eggs':.0555,'baffled-eggs':.0575,'skeptical-lids':.026,
  'smug-lids':.024,'cheeky-beans':.018,'bashful-squeeze':.038,'averted-eggs':.045,
  'warm-lids':.087,'longing-beans':.043,'annoyed-beans':.027,'irritated-beans':.023,
  'grumpy-beans':.026,'angry-squeeze':.055,'letdown-lids':.035,'sad-lids':.077,
  'crying-lids':.091,'pleading-eyes':.059,'hurt-eggs':.050,'cautious-eggs':.050,
  'scared-water':.080,'welling-eyes':.068,'surprise-dots':.058,'shook-ovals':.029,
  'stare-lids':.038,'hopeful-eggs':.060,'released-lids':.089,'uneasy-almonds':.050,
  'wince-lids':.055,'overloaded-eggs':.060,'rosy-beans':.016,'blank-water':.019
};
const mouthDimensions={
  'tiny-ring':[.018,.026],'little-bean':[.046,.061],'baby-w':[.076,.037],
  'tiny-frown':[.031,.031],'baby-yawn':[.036,.049],'spent-pout':[.046,.009],
  'happy-u':[.076,.121],'wide-laugh':[.135,.107],'crooked-grin':[.086,.060],
  'small-u-line':[.044,.029],'firm-w':[.062,.024],'tilted-o':[.020,.031],
  'little-triangle':[.037,.037],'shook-triangle':[.037,.037],'tiny-triangle':[.031,.037],
  'crooked-pout':[.043,.020],'curled-smirk':[.075,.032],'puckered-three':[.074,.064],
  'tiny-v':[.028,.048],'awkward-w':[.058,.031],'warm-w':[.068,.036],
  'small-pout':[.032,.030],'pushed-pout':[.043,.021],'tense-pout':[.052,.034],
  'grumpy-pout':[.065,.039],'protest-bean':[.074,.075],'sad-pout':[.035,.028],
  'quivering-pout':[.047,.031],'complaining-pout':[.062,.052],'hurt-pout':[.033,.033],
  'uneasy-wave':[.058,.024],'fear-wave':[.079,.032],'frightened-pout':[.070,.081],
  'round-gasp':[.035,.047],'tiny-caret':[.030,.030],'exhale-bean':[.048,.050],
  'side-blep':[.053,.036],'blank-line':[.041,.002],'small-waver':[.062,.024]
};

export function faceTarget(profile) {
  const art=profile.art,[mouthWidth,curve]=mouthDimensions[art.mouth];
  return {eyeX:art.eyeX,eyeY:art.eyeY,eyeOpen:eyeDimensions[art.eyes],mouthY:art.mouthY,
    mouthWidth,curve,cheekAlpha:art.cheeks==='none'?0:1,tearAmount:profile.tears==='none'?0:1};
}
