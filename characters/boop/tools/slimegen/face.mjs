// Each expression's face as the board's controls: where its eyes and mouth
// sit, and the sizes its art draws them at, which the board's springs move
// between and its drawn ratios are over. The sizes are read off the face
// painter's art primitives (painter.mjs): at rest each ratio is one,
// preserving the authored face.
const eyeDimensions={
  'soft-dot':.049,'sleepy-lid':.041,'pleased-bean':.022,'happy-dot':.046,
  'laugh-lid':.123,'amused-wink':.068,'curious-eggs':.0555,'attentive-eggs':.058,
  'gentle-resolve':.056,'smug-lids':.024,'cheeky-beans':.018,'warm-lids':.087,
  'longing-beans':.043,'annoyed-beans':.027,'grumpy-beans':.026,'angry-squeeze':.055,
  'sad-lids':.077,'hurt-eggs':.050,'surprise-dots':.058,
  'flat-lids':.033,'side-glance':.031,'slits':.014,'smug-half':.031,'scream-eggs':.074,'x-eyes':.038
};
const mouthDimensions={
  'tiny-ring':[.018,.026],'baby-w':[.076,.037],'baby-yawn':[.036,.049],
  'happy-u':[.076,.121],'wide-laugh':[.135,.107],'crooked-grin':[.086,.060],
  'small-u-line':[.044,.029],'firm-w':[.062,.024],'peering-o':[.024,.034],
  'curled-smirk':[.075,.032],'puckered-three':[.074,.064],'warm-w':[.068,.036],
  'small-pout':[.032,.030],'pushed-pout':[.043,.021],'grumpy-pout':[.065,.039],
  'protest-bean':[.074,.075],'sad-pout':[.035,.028],'hurt-pout':[.033,.033],
  'round-gasp':[.035,.047],
  'flat-line':[.050,.012],'side-line':[.058,.012],'wavy-line':[.060,.026],'cat-w':[.074,.044],'scream-o':[.068,.112]
};

export function faceTarget(profile) {
  const art=profile.art,[mouthWidth,curve]=mouthDimensions[art.mouth];
  return {eyeX:art.eyeX,eyeY:art.eyeY,eyeOpen:eyeDimensions[art.eyes],mouthY:art.mouthY,
    mouthWidth,curve,cheekAlpha:art.cheeks==='none'?0:1,tearAmount:profile.tears==='none'?0:1};
}
