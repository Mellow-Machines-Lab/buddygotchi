// Boop V4 procedural SVG + audio. No recordings, network, or API keys.
globalThis.Boop=(()=>{const modules={"audio/alert-presets.mjs":()=>{
// Attention signals, not success fanfares. All layers are synthesized locally.
const tone=(at,duration,freq,amp,extra={})=>({at,duration,freq,amp,wave:'sine',attack:.001,decay:duration*.18,...extra});
const noise=(at,duration,amp,extra={})=>({at,duration,amp,wave:'noise',highpass:900,lowpass:7200,attack:.0003,decay:duration*.15,...extra});
const recipe=(duration,...layers)=>({duration,layers:layers.flat()});
const alertEffects={
  alertSoftTap:recipe(.16,noise(0,.065,.34,{highpass:450,lowpass:3600,attack:.003,decay:.012}),tone(.003,.10,640,.12,{decay:.016})),
  alertPaperTap:recipe(.20,noise(0,.02,.38,{highpass:1300,decay:.004}),noise(.012,.12,.16,{highpass:800,lowpass:5700,decay:.025}),tone(.003,.065,910,.08,{decay:.012})),
  alertKeyboardTap:recipe(.18,noise(0,.018,.66,{highpass:1800,decay:.003}),noise(.015,.045,.28,{highpass:1000,decay:.008}),noise(.060,.035,.14,{highpass:2200,decay:.007}),tone(.002,.07,780,.16,{decay:.012})),
  alertBrickTap:recipe(.19,noise(0,.028,.64,{highpass:800,lowpass:4700,decay:.006}),noise(.018,.10,.22,{highpass:1800,lowpass:7000,decay:.019}),tone(.002,.10,420,.16,{decay:.020}),tone(.004,.045,1410,.06,{decay:.009})),
  alertRubberTap:recipe(.16,tone(0,.11,940,.16,{end:620,decay:.025}),noise(0,.03,.34,{highpass:900,lowpass:4300,decay:.006})),
  alertKnock:recipe(.24,
    noise(0,.022,.64,{highpass:1200,decay:.004}),noise(.004,.066,.22,{highpass:550,lowpass:4400,decay:.012}),
    tone(.002,.12,720,.22,{decay:.018}),tone(.003,.08,1730,.11,{decay:.011}),tone(.005,.046,2970,.05,{decay:.007})),
  alertDing:recipe(.88,
    tone(0,.80,1046.50,.31,{decay:.17}),tone(0,.64,2093,.085,{decay:.12}),
    tone(.002,.40,2911,.040,{decay:.06}),tone(.004,.38,523.25,.07,{decay:.07}),
    noise(0,.013,.14,{highpass:2300,decay:.002})),
  alertDong:recipe(1.02,
    tone(0,.95,783.99,.29,{decay:.20}),tone(.002,.65,1567.98,.080,{decay:.13}),
    tone(.003,.43,2181,.041,{decay:.085}),tone(.005,.40,392,.085,{decay:.065}),
    noise(0,.014,.13,{highpass:1700,decay:.0025})),
  alertBell:recipe(.98,
    tone(0,.90,1174.66,.27,{decay:.18}),tone(.002,.61,1902.95,.105,{decay:.11}),
    tone(.003,.40,3218.57,.051,{decay:.067}),tone(.005,.48,587.33,.09,{decay:.080}),
    noise(0,.016,.23,{highpass:1900,decay:.003}))
};

return {alertEffects};},
"audio/approved-presets.mjs":()=>{
// Frozen V4 procedural recipes. Numbers describe oscillators and noise envelopes, not recorded samples.
const approved = {"key":{"duration":0.043,"layers":[{"at":0,"duration":0.009,"amp":0.7904,"wave":"noise","lowpass":10500,"highpass":2200,"attack":0.00012,"decay":0.00165,"release":0.002},{"at":0.0025,"duration":0.024,"amp":0.41600000000000004,"wave":"noise","lowpass":6200,"highpass":650,"attack":0.0002,"decay":0.0045,"release":0.004},{"at":0.003,"duration":0.035,"freq":780,"amp":0.156,"wave":"sine","attack":0.0002,"decay":0.0045},{"at":0.003,"duration":0.024,"freq":1890,"amp":0.10400000000000001,"wave":"sine","attack":0.00015,"decay":0.003},{"at":0.001,"duration":0.014,"freq":3540,"amp":0.0468,"wave":"sine","attack":0.0001,"decay":0.0018}]},"softKey":{"duration":0.043,"layers":[{"at":0,"duration":0.009,"amp":0.5599193600000001,"wave":"noise","lowpass":10500,"highpass":2200,"attack":0.00012,"decay":0.00165,"release":0.002},{"at":0.0025,"duration":0.024,"amp":0.32032000000000005,"wave":"noise","lowpass":6200,"highpass":650,"attack":0.0002,"decay":0.0045,"release":0.004},{"at":0.003,"duration":0.035,"freq":709.8000000000001,"amp":0.12012,"wave":"sine","attack":0.0002,"decay":0.0045},{"at":0.003,"duration":0.024,"freq":1719.9,"amp":0.08008000000000001,"wave":"sine","attack":0.00015,"decay":0.003},{"at":0.001,"duration":0.014,"freq":3221.4,"amp":0.036036,"wave":"sine","attack":0.0001,"decay":0.0018}]},"bash":{"duration":0.18,"layers":[{"at":0,"duration":0.018,"amp":0.88,"wave":"noise","lowpass":11000,"highpass":1300,"attack":0.0001,"decay":0.0031},{"at":0.005,"duration":0.052,"amp":0.41,"wave":"noise","lowpass":6500,"highpass":750,"attack":0.0001,"decay":0.009},{"at":0.016,"duration":0.024,"amp":0.38,"wave":"noise","lowpass":9400,"highpass":1500,"attack":0.00015,"decay":0.0035},{"at":0.029,"duration":0.024,"amp":0.332,"wave":"noise","lowpass":8950,"highpass":1500,"attack":0.00015,"decay":0.0035},{"at":0.047,"duration":0.024,"amp":0.28400000000000003,"wave":"noise","lowpass":8500,"highpass":1500,"attack":0.00015,"decay":0.0035},{"at":0.072,"duration":0.024,"amp":0.236,"wave":"noise","lowpass":8050,"highpass":1500,"attack":0.00015,"decay":0.0035},{"at":0.105,"duration":0.024,"amp":0.188,"wave":"noise","lowpass":7600,"highpass":1500,"attack":0.00015,"decay":0.0035},{"at":0.003,"duration":0.02,"freq":1840,"amp":0.065,"wave":"sine","attack":0.0001,"decay":0.0025}]},"snap":{"duration":0.32,"layers":[{"at":0,"duration":0.017,"amp":0.98,"wave":"noise","lowpass":11600,"highpass":1050,"attack":0.0001,"decay":0.0034},{"at":0.004,"duration":0.068,"amp":0.52,"wave":"noise","lowpass":5900,"highpass":700,"attack":0.0001,"decay":0.01},{"at":0.013,"duration":0.028,"amp":0.43,"wave":"noise","lowpass":9200,"highpass":1100,"attack":0.0001,"decay":0.004},{"at":0.023,"duration":0.028,"amp":0.386,"wave":"noise","lowpass":9200,"highpass":1190,"attack":0.0001,"decay":0.004},{"at":0.042,"duration":0.028,"amp":0.34199999999999997,"wave":"noise","lowpass":9200,"highpass":1280,"attack":0.0001,"decay":0.004},{"at":0.06,"duration":0.028,"amp":0.298,"wave":"noise","lowpass":9200,"highpass":1370,"attack":0.0001,"decay":0.004},{"at":0.094,"duration":0.028,"amp":0.254,"wave":"noise","lowpass":9200,"highpass":1460,"attack":0.0001,"decay":0.004},{"at":0.131,"duration":0.028,"amp":0.21000000000000002,"wave":"noise","lowpass":9200,"highpass":1550,"attack":0.0001,"decay":0.004},{"at":0.179,"duration":0.028,"amp":0.16599999999999998,"wave":"noise","lowpass":9200,"highpass":1640,"attack":0.0001,"decay":0.004},{"at":0.231,"duration":0.028,"amp":0.122,"wave":"noise","lowpass":9200,"highpass":1730,"attack":0.0001,"decay":0.004},{"at":0.005,"duration":0.025,"freq":2170,"amp":0.068,"wave":"sine","attack":0.0001,"decay":0.003}]},"keycap":{"duration":0.11,"layers":[{"at":0,"duration":0.019,"amp":0.39,"wave":"noise","lowpass":10600,"highpass":1800,"attack":0.0001,"decay":0.003},{"at":0.001,"duration":0.021,"freq":2590,"amp":0.06,"wave":"sine","decay":0.0027},{"at":0.048,"duration":0.015,"amp":0.16,"wave":"noise","lowpass":8400,"highpass":2400,"decay":0.0025}]},"whoosh":{"duration":0.27,"layers":[{"at":0,"duration":0.24,"amp":0.21,"wave":"noise","lowpass":4900,"filterEnd":0.12,"attack":0.047,"decay":0.1,"release":0.07}]},"landing":{"duration":0.16,"layers":[{"at":0,"duration":0.03,"amp":0.29,"wave":"noise","lowpass":5700,"highpass":700,"attack":0.00015,"decay":0.0045},{"at":0.022,"duration":0.03,"amp":0.243,"wave":"noise","lowpass":5700,"highpass":700,"attack":0.00015,"decay":0.0045},{"at":0.053,"duration":0.03,"amp":0.19599999999999998,"wave":"noise","lowpass":5700,"highpass":700,"attack":0.00015,"decay":0.0045},{"at":0.09,"duration":0.03,"amp":0.14899999999999997,"wave":"noise","lowpass":5700,"highpass":700,"attack":0.00015,"decay":0.0045}]},"drop":{"duration":0.19,"layers":[{"at":0,"duration":0.16,"freq":980,"amp":0.14,"wave":"sine","end":330,"decay":0.038},{"at":0.009,"duration":0.08,"freq":1750,"amp":0.035,"wave":"sine","end":780,"decay":0.016}]},"splash":{"duration":0.26,"layers":[{"at":0,"duration":0.19,"amp":0.2,"wave":"noise","lowpass":3100,"filterEnd":0.27,"decay":0.049},{"at":0.013,"duration":0.16,"freq":730,"amp":0.12,"wave":"sine","end":260,"decay":0.036},{"at":0.056,"duration":0.15,"freq":1120,"amp":0.055,"wave":"sine","end":370,"decay":0.028}]},"short":{"duration":0.26,"layers":[{"at":0,"duration":0.052,"amp":0.16,"wave":"noise","lowpass":5600,"hold":4,"decay":0.015},{"at":0.005,"duration":0.081,"freq":880,"amp":0.13,"wave":"pulse","steps":[1175,880,415],"decay":0.028,"lowpass":3800},{"at":0.086,"duration":0.055,"amp":0.12,"wave":"noise","lowpass":4300,"hold":5,"decay":0.013},{"at":0.15,"duration":0.065,"freq":440,"amp":0.075,"wave":"pulse","end":196,"decay":0.018,"lowpass":2400}]},"keyB":{"duration":0.043,"layers":[{"at":0,"duration":0.009,"amp":0.727168,"wave":"noise","lowpass":10500,"highpass":2200,"attack":0.00012,"decay":0.00165,"release":0.002},{"at":0.0025,"duration":0.024,"amp":0.41600000000000004,"wave":"noise","lowpass":6200,"highpass":650,"attack":0.0002,"decay":0.0045,"release":0.004},{"at":0.003,"duration":0.035,"freq":709.8000000000001,"amp":0.156,"wave":"sine","attack":0.0002,"decay":0.0045},{"at":0.003,"duration":0.024,"freq":1719.9,"amp":0.10400000000000001,"wave":"sine","attack":0.00015,"decay":0.003},{"at":0.001,"duration":0.014,"freq":3221.4,"amp":0.0468,"wave":"sine","attack":0.0001,"decay":0.0018}]},"keyC":{"duration":0.043,"layers":[{"at":0,"duration":0.009,"amp":0.822016,"wave":"noise","lowpass":10500,"highpass":2200,"attack":0.00012,"decay":0.00165,"release":0.002},{"at":0.0025,"duration":0.024,"amp":0.41600000000000004,"wave":"noise","lowpass":6200,"highpass":650,"attack":0.0002,"decay":0.0045,"release":0.004},{"at":0.003,"duration":0.035,"freq":858.0000000000001,"amp":0.156,"wave":"sine","attack":0.0002,"decay":0.0045},{"at":0.003,"duration":0.024,"freq":2079,"amp":0.10400000000000001,"wave":"sine","attack":0.00015,"decay":0.003},{"at":0.001,"duration":0.014,"freq":3894.0000000000005,"amp":0.0468,"wave":"sine","attack":0.0001,"decay":0.0018}]},"space":{"duration":0.043,"layers":[{"at":0,"duration":0.009,"amp":0.6323200000000001,"wave":"noise","lowpass":10500,"highpass":2200,"attack":0.00012,"decay":0.00165,"release":0.002},{"at":0.0025,"duration":0.024,"amp":0.41600000000000004,"wave":"noise","lowpass":6200,"highpass":650,"attack":0.0002,"decay":0.0045,"release":0.004},{"at":0.003,"duration":0.035,"freq":530.4000000000001,"amp":0.156,"wave":"sine","attack":0.0002,"decay":0.0045},{"at":0.003,"duration":0.024,"freq":1285.2,"amp":0.10400000000000001,"wave":"sine","attack":0.00015,"decay":0.003},{"at":0.001,"duration":0.014,"freq":2407.2000000000003,"amp":0.0468,"wave":"sine","attack":0.0001,"decay":0.0018},{"at":0.003,"duration":0.039999999999999994,"amp":0.2288,"wave":"noise","lowpass":4300,"highpass":350,"attack":0.0003,"decay":0.008},{"at":0.005,"duration":0.038,"freq":420,"amp":0.13520000000000001,"wave":"sine","attack":0.0004,"decay":0.01}]},"trophyA":{"duration":2.3,"layers":[{"at":0,"duration":0.16,"freq":523.2511306011972,"amp":0.12,"wave":"pulse","attack":0.012,"decay":0.24800000000000003,"release":0.09,"lowpass":3300},{"at":0.006,"duration":0.154,"freq":526.3906373848044,"amp":0.0324,"wave":"square","attack":0.018,"decay":0.16,"release":0.08,"lowpass":2400},{"at":0,"duration":0.16,"freq":261.6255653005986,"amp":0.0384,"wave":"triangle","attack":0.008,"decay":0.1152,"release":0.08},{"at":0.16,"duration":0.16,"freq":659.2551138257398,"amp":0.12,"wave":"pulse","attack":0.012,"decay":0.24800000000000003,"release":0.09,"lowpass":3300},{"at":0.166,"duration":0.154,"freq":663.2106445086943,"amp":0.0324,"wave":"square","attack":0.018,"decay":0.16,"release":0.08,"lowpass":2400},{"at":0.16,"duration":0.16,"freq":329.6275569128699,"amp":0.0384,"wave":"triangle","attack":0.008,"decay":0.1152,"release":0.08},{"at":0.32,"duration":0.18,"freq":783.9908719634985,"amp":0.12,"wave":"pulse","attack":0.012,"decay":0.27899999999999997,"release":0.09,"lowpass":3300},{"at":0.326,"duration":0.174,"freq":788.6948171952795,"amp":0.0324,"wave":"square","attack":0.018,"decay":0.18,"release":0.08,"lowpass":2400},{"at":0.32,"duration":0.18,"freq":391.99543598174927,"amp":0.0384,"wave":"triangle","attack":0.008,"decay":0.1296,"release":0.08},{"at":0.52,"duration":1.1,"freq":261.6255653005986,"amp":0.075,"wave":"pulse","attack":0.012,"decay":1.7050000000000003,"release":0.09,"lowpass":3300},{"at":0.526,"duration":1.094,"freq":263.1953186924022,"amp":0.02025,"wave":"square","attack":0.018,"decay":1.1,"release":0.08,"lowpass":2400},{"at":0.52,"duration":1.1,"freq":130.8127826502993,"amp":0.024,"wave":"triangle","attack":0.008,"decay":0.792,"release":0.08},{"at":0.52,"duration":1.1,"freq":329.6275569128699,"amp":0.075,"wave":"pulse","attack":0.012,"decay":1.7050000000000003,"release":0.09,"lowpass":3300},{"at":0.526,"duration":1.094,"freq":331.60532225434713,"amp":0.02025,"wave":"square","attack":0.018,"decay":1.1,"release":0.08,"lowpass":2400},{"at":0.52,"duration":1.1,"freq":164.81377845643496,"amp":0.024,"wave":"triangle","attack":0.008,"decay":0.792,"release":0.08},{"at":0.52,"duration":1.1,"freq":391.99543598174927,"amp":0.075,"wave":"pulse","attack":0.012,"decay":1.7050000000000003,"release":0.09,"lowpass":3300},{"at":0.526,"duration":1.094,"freq":394.34740859763974,"amp":0.02025,"wave":"square","attack":0.018,"decay":1.1,"release":0.08,"lowpass":2400},{"at":0.52,"duration":1.1,"freq":195.99771799087463,"amp":0.024,"wave":"triangle","attack":0.008,"decay":0.792,"release":0.08},{"at":0.52,"duration":1.1,"freq":523.2511306011972,"amp":0.14,"wave":"pulse","attack":0.012,"decay":1.7050000000000003,"release":0.09,"lowpass":3300},{"at":0.526,"duration":1.094,"freq":526.3906373848044,"amp":0.03780000000000001,"wave":"square","attack":0.018,"decay":1.1,"release":0.08,"lowpass":2400},{"at":0.52,"duration":1.1,"freq":261.6255653005986,"amp":0.044800000000000006,"wave":"triangle","attack":0.008,"decay":0.792,"release":0.08},{"at":0.52,"duration":0.42,"freq":130.81,"amp":0.15,"wave":"triangle","attack":0.004,"decay":0.09},{"at":0.51,"duration":0.85,"amp":0.2,"wave":"noise","lowpass":11200,"highpass":2100,"attack":0.002,"decay":0.19,"release":0.2},{"at":0.17,"duration":0.055,"amp":0.14,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.18200000000000002,"duration":0.065,"amp":0.07840000000000001,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.34,"duration":0.055,"amp":0.17,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.35200000000000004,"duration":0.065,"amp":0.09520000000000002,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.73,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.742,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.7948235294117647,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.8068235294117647,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.8596470588235294,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.8716470588235294,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.9104705882352941,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.9224705882352942,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.9752941176470589,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.9872941176470589,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.0261176470588236,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.0381176470588236,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.0909411764705883,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.1029411764705883,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.1417647058823528,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.1537647058823528,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.2065882352941177,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.2185882352941177,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.2714117647058822,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.2834117647058823,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.3222352941176472,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.3342352941176472,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.3870588235294117,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.3990588235294117,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.4378823529411766,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.4498823529411766,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.5027058823529411,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.5147058823529411,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.5535294117647058,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.5655294117647058,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.6183529411764705,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.6303529411764706,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.6831764705882353,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.6951764705882353,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.734,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.746,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.7988235294117647,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.8108235294117647,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.18,"duration":0.62,"freq":1567.98,"amp":0.048,"wave":"triangle","attack":0.003,"decay":0.13}]},"trophyB":{"duration":2.85,"layers":[{"at":0,"duration":0.16,"freq":261.6255653005986,"amp":0.07,"wave":"pulse","attack":0.012,"decay":0.24800000000000003,"release":0.09,"lowpass":3300},{"at":0.006,"duration":0.154,"freq":263.1953186924022,"amp":0.018900000000000004,"wave":"square","attack":0.018,"decay":0.16,"release":0.08,"lowpass":2400},{"at":0,"duration":0.16,"freq":130.8127826502993,"amp":0.022400000000000003,"wave":"triangle","attack":0.008,"decay":0.1152,"release":0.08},{"at":0,"duration":0.16,"freq":329.6275569128699,"amp":0.07,"wave":"pulse","attack":0.012,"decay":0.24800000000000003,"release":0.09,"lowpass":3300},{"at":0.006,"duration":0.154,"freq":331.60532225434713,"amp":0.018900000000000004,"wave":"square","attack":0.018,"decay":0.16,"release":0.08,"lowpass":2400},{"at":0,"duration":0.16,"freq":164.81377845643496,"amp":0.022400000000000003,"wave":"triangle","attack":0.008,"decay":0.1152,"release":0.08},{"at":0,"duration":0.16,"freq":391.99543598174927,"amp":0.07,"wave":"pulse","attack":0.012,"decay":0.24800000000000003,"release":0.09,"lowpass":3300},{"at":0.006,"duration":0.154,"freq":394.34740859763974,"amp":0.018900000000000004,"wave":"square","attack":0.018,"decay":0.16,"release":0.08,"lowpass":2400},{"at":0,"duration":0.16,"freq":195.99771799087463,"amp":0.022400000000000003,"wave":"triangle","attack":0.008,"decay":0.1152,"release":0.08},{"at":0.2,"duration":0.19,"freq":349.2282314330039,"amp":0.072,"wave":"pulse","attack":0.012,"decay":0.29450000000000004,"release":0.09,"lowpass":3300},{"at":0.20600000000000002,"duration":0.184,"freq":351.32360082160193,"amp":0.01944,"wave":"square","attack":0.018,"decay":0.19,"release":0.08,"lowpass":2400},{"at":0.2,"duration":0.19,"freq":174.61411571650194,"amp":0.023039999999999998,"wave":"triangle","attack":0.008,"decay":0.1368,"release":0.08},{"at":0.2,"duration":0.19,"freq":440,"amp":0.072,"wave":"pulse","attack":0.012,"decay":0.29450000000000004,"release":0.09,"lowpass":3300},{"at":0.20600000000000002,"duration":0.184,"freq":442.64,"amp":0.01944,"wave":"square","attack":0.018,"decay":0.19,"release":0.08,"lowpass":2400},{"at":0.2,"duration":0.19,"freq":220,"amp":0.023039999999999998,"wave":"triangle","attack":0.008,"decay":0.1368,"release":0.08},{"at":0.2,"duration":0.19,"freq":523.2511306011972,"amp":0.072,"wave":"pulse","attack":0.012,"decay":0.29450000000000004,"release":0.09,"lowpass":3300},{"at":0.20600000000000002,"duration":0.184,"freq":526.3906373848044,"amp":0.01944,"wave":"square","attack":0.018,"decay":0.19,"release":0.08,"lowpass":2400},{"at":0.2,"duration":0.19,"freq":261.6255653005986,"amp":0.023039999999999998,"wave":"triangle","attack":0.008,"decay":0.1368,"release":0.08},{"at":0.47,"duration":1.3,"freq":261.6255653005986,"amp":0.073,"wave":"pulse","attack":0.012,"decay":2.015,"release":0.09,"lowpass":3300},{"at":0.476,"duration":1.294,"freq":263.1953186924022,"amp":0.01971,"wave":"square","attack":0.018,"decay":1.3,"release":0.08,"lowpass":2400},{"at":0.47,"duration":1.3,"freq":130.8127826502993,"amp":0.02336,"wave":"triangle","attack":0.008,"decay":0.9359999999999999,"release":0.08},{"at":0.47,"duration":1.3,"freq":329.6275569128699,"amp":0.073,"wave":"pulse","attack":0.012,"decay":2.015,"release":0.09,"lowpass":3300},{"at":0.476,"duration":1.294,"freq":331.60532225434713,"amp":0.01971,"wave":"square","attack":0.018,"decay":1.3,"release":0.08,"lowpass":2400},{"at":0.47,"duration":1.3,"freq":164.81377845643496,"amp":0.02336,"wave":"triangle","attack":0.008,"decay":0.9359999999999999,"release":0.08},{"at":0.47,"duration":1.3,"freq":391.99543598174927,"amp":0.073,"wave":"pulse","attack":0.012,"decay":2.015,"release":0.09,"lowpass":3300},{"at":0.476,"duration":1.294,"freq":394.34740859763974,"amp":0.01971,"wave":"square","attack":0.018,"decay":1.3,"release":0.08,"lowpass":2400},{"at":0.47,"duration":1.3,"freq":195.99771799087463,"amp":0.02336,"wave":"triangle","attack":0.008,"decay":0.9359999999999999,"release":0.08},{"at":0.47,"duration":1.3,"freq":523.2511306011972,"amp":0.135,"wave":"pulse","attack":0.012,"decay":2.015,"release":0.09,"lowpass":3300},{"at":0.476,"duration":1.294,"freq":526.3906373848044,"amp":0.03645,"wave":"square","attack":0.018,"decay":1.3,"release":0.08,"lowpass":2400},{"at":0.47,"duration":1.3,"freq":261.6255653005986,"amp":0.0432,"wave":"triangle","attack":0.008,"decay":0.9359999999999999,"release":0.08},{"at":0.47,"duration":0.42,"freq":130.81,"amp":0.16,"wave":"triangle","attack":0.003,"decay":0.085},{"at":0.46,"duration":1.08,"amp":0.19,"wave":"noise","lowpass":10500,"highpass":2000,"attack":0.003,"decay":0.24,"release":0.23},{"at":0.57,"duration":1.75,"freq":178,"amp":0.006522591428182049,"wave":"sine","end":183.34,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":356,"amp":0.005131388562551798,"wave":"sine","end":366.68,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":534,"amp":0.00795920519781079,"wave":"sine","end":550.02,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":712,"amp":0.011347520443991765,"wave":"sine","end":733.36,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":890,"amp":0.011636001933923902,"wave":"sine","end":916.7,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":1068,"amp":0.01009431693249748,"wave":"sine","end":1100.04,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":1246,"amp":0.009128221622879362,"wave":"sine","end":1283.38,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":1424,"amp":0.007614280316774988,"wave":"sine","end":1466.72,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":1602,"amp":0.004944191852429573,"wave":"sine","end":1650.06,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":1780,"amp":0.0026536871714049073,"wave":"sine","end":1833.4,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":1958,"amp":0.0017651348895514484,"wave":"sine","end":2016.74,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":2136,"amp":0.0019818998852003606,"wave":"sine","end":2200.08,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.57,"duration":1.75,"freq":2314,"amp":0.0026270412064040055,"wave":"sine","end":2383.42,"attack":0.1,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":4.8},{"at":0.606,"duration":1.714,"freq":204,"amp":0.006651393936251885,"wave":"sine","end":211.752,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":408,"amp":0.006044521328713854,"wave":"sine","end":423.504,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":612,"amp":0.009914147971604812,"wave":"sine","end":635.256,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":816,"amp":0.012130409506464015,"wave":"sine","end":847.008,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":1020,"amp":0.010642993984939201,"wave":"sine","end":1058.76,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":1224,"amp":0.009366646683537433,"wave":"sine","end":1270.512,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":1428,"amp":0.007674852875630757,"wave":"sine","end":1482.2640000000001,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":1632,"amp":0.004581611566065648,"wave":"sine","end":1694.016,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":1836,"amp":0.0023049726434412857,"wave":"sine","end":1905.768,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":2040,"amp":0.001847296450678121,"wave":"sine","end":2117.52,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":2244,"amp":0.002432460133955745,"wave":"sine","end":2329.272,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":2448,"amp":0.003115602076472087,"wave":"sine","end":2541.024,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.606,"duration":1.714,"freq":2652,"amp":0.0032562605957036353,"wave":"sine","end":2752.7760000000003,"attack":0.112,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.13},{"at":0.6419999999999999,"duration":1.678,"freq":229,"amp":0.0068050107135754585,"wave":"sine","end":239.53400000000002,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":458,"amp":0.007110082796174744,"wave":"sine","end":479.06800000000004,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":687,"amp":0.011466333112432324,"wave":"sine","end":718.602,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":916,"amp":0.011776748916286266,"wave":"sine","end":958.1360000000001,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":1145,"amp":0.009885773097983401,"wave":"sine","end":1197.67,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":1374,"amp":0.008412227616168092,"wave":"sine","end":1437.204,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":1603,"amp":0.005123025551068862,"wave":"sine","end":1676.738,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":1832,"amp":0.0024146273780255765,"wave":"sine","end":1916.2720000000002,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":2061,"amp":0.0019514412596258717,"wave":"sine","end":2155.806,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":2290,"amp":0.002673157426192369,"wave":"sine","end":2395.34,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":2519,"amp":0.003307031252873709,"wave":"sine","end":2634.8740000000003,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":2748,"amp":0.003124027879588289,"wave":"sine","end":2874.408,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6419999999999999,"duration":1.678,"freq":2977,"amp":0.00222730365441012,"wave":"sine","end":3113.942,"attack":0.124,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.46},{"at":0.6779999999999999,"duration":1.642,"freq":251,"amp":0.006967837187965853,"wave":"sine","end":258.53000000000003,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":502,"amp":0.008167127183026677,"wave":"sine","end":517.0600000000001,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":753,"amp":0.012329792242006993,"wave":"sine","end":775.59,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":1004,"amp":0.011075698962941723,"wave":"sine","end":1034.1200000000001,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":1255,"amp":0.009436594522557656,"wave":"sine","end":1292.65,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":1506,"amp":0.006752519055862526,"wave":"sine","end":1551.18,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":1757,"amp":0.003130294845136642,"wave":"sine","end":1809.71,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":2008,"amp":0.0019660788777764848,"wave":"sine","end":2068.2400000000002,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":2259,"amp":0.002616369711321675,"wave":"sine","end":2326.77,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":2510,"amp":0.003348726801908494,"wave":"sine","end":2585.3,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":2761,"amp":0.0031358283591898,"wave":"sine","end":2843.83,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":3012,"amp":0.002113166501844953,"wave":"sine","end":3102.36,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.6779999999999999,"duration":1.642,"freq":3263,"amp":0.0011274340472313378,"wave":"sine","end":3360.89,"attack":0.136,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":5.79},{"at":0.714,"duration":1.606,"freq":277,"amp":0.007197794374353347,"wave":"sine","end":287.526,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":554,"amp":0.00949023038285676,"wave":"sine","end":575.052,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":831,"amp":0.012643747806650538,"wave":"sine","end":862.578,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":1108,"amp":0.010368539715519204,"wave":"sine","end":1150.104,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":1385,"amp":0.008506872537938043,"wave":"sine","end":1437.63,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":1662,"amp":0.004410075488777512,"wave":"sine","end":1725.156,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":1939,"amp":0.0021076214376668963,"wave":"sine","end":2012.682,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":2216,"amp":0.002529142858633763,"wave":"sine","end":2300.208,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":2493,"amp":0.003386721848517885,"wave":"sine","end":2587.734,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":2770,"amp":0.0031660965924389895,"wave":"sine","end":2875.26,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":3047,"amp":0.0020077186365212323,"wave":"sine","end":3162.786,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":3324,"amp":0.0010062253889958348,"wave":"sine","end":3450.312,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.714,"duration":1.606,"freq":3601,"amp":0.0005724904248062228,"wave":"sine","end":3737.838,"attack":0.14800000000000002,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.12},{"at":0.75,"duration":1.57,"freq":306,"amp":0.007507445628385978,"wave":"sine","end":320.076,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":612,"amp":0.01093266649012333,"wave":"sine","end":640.152,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":918,"amp":0.012271931614888135,"wave":"sine","end":960.2280000000001,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":1224,"amp":0.009875905942796692,"wave":"sine","end":1280.304,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":1530,"amp":0.006594488085610647,"wave":"sine","end":1600.38,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":1836,"amp":0.0026444788162807917,"wave":"sine","end":1920.4560000000001,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":2142,"amp":0.0023654509814414284,"wave":"sine","end":2240.532,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":2448,"amp":0.0033702317061017166,"wave":"sine","end":2560.608,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":2754,"amp":0.003278163652173385,"wave":"sine","end":2880.684,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":3060,"amp":0.0020077599863472235,"wave":"sine","end":3200.76,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":3366,"amp":0.0009596488754917464,"wave":"sine","end":3520.8360000000002,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":3672,"amp":0.0005722117121530592,"wave":"sine","end":3840.9120000000003,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.75,"duration":1.57,"freq":3978,"amp":0.00047536603254272824,"wave":"sine","end":4160.988,"attack":0.16,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.45},{"at":0.7859999999999999,"duration":1.534,"freq":329,"amp":0.007796270421523737,"wave":"sine","end":338.87,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":658,"amp":0.011944897412891172,"wave":"sine","end":677.74,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":987,"amp":0.011723961743629822,"wave":"sine","end":1016.61,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":1316,"amp":0.00939772087706051,"wave":"sine","end":1355.48,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":1645,"amp":0.00485219357300952,"wave":"sine","end":1694.3500000000001,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":1974,"amp":0.0022169226213402627,"wave":"sine","end":2033.22,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":2303,"amp":0.0029867399249802673,"wave":"sine","end":2372.09,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":2632,"amp":0.003565612189300754,"wave":"sine","end":2710.96,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":2961,"amp":0.002506179429068966,"wave":"sine","end":3049.83,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":3290,"amp":0.0011936819559485773,"wave":"sine","end":3388.7000000000003,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":3619,"amp":0.0006463625896195715,"wave":"sine","end":3727.57,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":3948,"amp":0.0005161790098382294,"wave":"sine","end":4066.44,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.7859999999999999,"duration":1.534,"freq":4277,"amp":0.0004703432574313984,"wave":"sine","end":4405.31,"attack":0.17200000000000001,"decay":1.2249999999999999,"release":0.22,"wobble":0.014,"wobbleHz":6.779999999999999},{"at":0.6299999999999999,"duration":1.69,"amp":0.08,"wave":"noise","lowpass":3800,"highpass":850,"attack":0.2,"decay":1.1375,"release":0.25},{"at":0.77,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.782,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.8194782608695652,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.8314782608695652,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.8689565217391304,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.8809565217391304,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.9044347826086957,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.9164347826086957,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.9539130434782609,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":0.9659130434782609,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":0.9893913043478261,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.001391304347826,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.0388695652173914,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.0508695652173914,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.0743478260869566,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.0863478260869566,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.1238260869565218,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.1358260869565218,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.173304347826087,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.185304347826087,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.2087826086956521,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.2207826086956521,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.2582608695652173,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.2702608695652173,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.2937391304347827,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.3057391304347827,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.3432173913043477,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.3552173913043477,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.378695652173913,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.390695652173913,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.4281739130434783,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.4401739130434783,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.4776521739130435,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.4896521739130435,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.5131304347826087,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.5251304347826087,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.5626086956521739,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.5746086956521739,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.5980869565217393,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.6100869565217393,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.6475652173913042,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.6595652173913042,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.6830434782608696,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.6950434782608697,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.7325217391304348,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.7445217391304348,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.782,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.794,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.8174782608695652,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.8294782608695652,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.8669565217391304,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.8789565217391304,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.9024347826086956,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.9144347826086956,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.951913043478261,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.963913043478261,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.9873913043478262,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":1.9993913043478262,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":2.036869565217391,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":2.048869565217391,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":2.0863478260869566,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":2.0983478260869566,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":2.121826086956522,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":2.133826086956522,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":2.1713043478260867,"duration":0.055,"amp":0.04872,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":2.1833043478260867,"duration":0.065,"amp":0.027283200000000004,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":2.2067826086956517,"duration":0.055,"amp":0.05278,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":2.2187826086956517,"duration":0.065,"amp":0.029556800000000005,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":2.2562608695652173,"duration":0.055,"amp":0.05684,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":2.2682608695652173,"duration":0.065,"amp":0.0318304,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":2.2917391304347827,"duration":0.055,"amp":0.0406,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":2.3037391304347827,"duration":0.065,"amp":0.022736,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":2.341217391304348,"duration":0.055,"amp":0.044660000000000005,"wave":"noise","lowpass":4900,"highpass":680,"attack":0.0005,"decay":0.012},{"at":2.353217391304348,"duration":0.065,"amp":0.025009600000000007,"wave":"noise","lowpass":6700,"highpass":950,"attack":0.0004,"decay":0.014},{"at":1.15,"duration":0.2,"freq":1046.5,"amp":0.045,"wave":"triangle","attack":0.002,"decay":0.055},{"at":1.32,"duration":0.2,"freq":1318.51,"amp":0.045,"wave":"triangle","attack":0.002,"decay":0.055},{"at":1.5,"duration":0.2,"freq":1567.98,"amp":0.045,"wave":"triangle","attack":0.002,"decay":0.055}]},"release":{"duration":0.035,"layers":[{"at":0,"duration":0.018,"amp":0.28,"wave":"noise","lowpass":9700,"highpass":1850,"attack":0.00012,"decay":0.0028},{"at":0.001,"duration":0.026,"freq":1630,"amp":0.068,"wave":"sine","attack":0.0002,"decay":0.0035}]},"creak":{"duration":0.135,"layers":[{"at":0,"duration":0.026,"amp":0.11,"wave":"noise","lowpass":3400,"highpass":800,"attack":0.002,"decay":0.006},{"at":0.019,"duration":0.026,"amp":0.129,"wave":"noise","lowpass":4200,"highpass":800,"attack":0.002,"decay":0.006},{"at":0.045,"duration":0.026,"amp":0.148,"wave":"noise","lowpass":5000,"highpass":800,"attack":0.002,"decay":0.006},{"at":0.08,"duration":0.026,"amp":0.16699999999999998,"wave":"noise","lowpass":5800,"highpass":800,"attack":0.002,"decay":0.006}]}};

return {approved};},
"audio/effects.mjs":()=>{
const {approved}=load("audio/approved-presets.mjs");
const {alertEffects}=load("audio/alert-presets.mjs");
const n=(at,duration,amp,extra={})=>({at,duration,amp,wave:'noise',lowpass:6500,highpass:800,attack:.0004,decay:duration*.16,...extra});
const t=(at,duration,freq,amp,extra={})=>({at,duration,freq,amp,wave:'sine',attack:.001,decay:duration*.14,...extra});
const r=(duration,...layers)=>({duration,layers:layers.flat()});
const grain=(length,count,amp,hp=700,lp=6000)=>Array.from({length:count},(_,i)=>n(i*length/count,.025+(i%3)*.009,amp*(.75+(i%4)*.08),{highpass:hp,lowpass:lp,decay:.005}));
const brass=(at,duration,f,amp)=>[t(at,duration,f,amp,{wave:'pulse',attack:.012,decay:duration,release:.1,lowpass:3200}),t(at+.006,duration-.006,f*1.006,amp*.3,{wave:'square',attack:.018,decay:duration*.8,release:.1,lowpass:2300}),t(at,duration,f*.5,amp*.32,{wave:'triangle',attack:.012,decay:duration*.5})];
const applause=(at,length)=>Array.from({length:Math.floor(length*19)},(_,i)=>n(at+i/19+((i*7)%5)*.002,.075,.06+(i%3)*.005,{highpass:750,lowpass:5400,decay:.014}));

const effects={...approved,...alertEffects,
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
  victoryPodium:r(2.65,
    brass(0,.20,261.63,.075),brass(.80,.20,392,.078),
    ...[261.63,329.63,392,523.25].flatMap((f,i)=>brass(1.60,.78,f,i===3?.145:.075)),
    n(1.59,.85,.20,{highpass:2100,lowpass:11000,decay:.20,release:.20}),
    ...applause(1.71,.83),t(1.60,.40,130.81,.14,{wave:'triangle',decay:.09}))
};

function effectRecipe(name,pitch=1){
  const base=effects[name];if(!base)throw new Error('Unknown effect: '+name);
  if(pitch===1)return base;
  return {...base,layers:base.layers.map(layer=>({...layer,...(layer.freq?{freq:layer.freq*pitch}:{}),...(layer.end?{end:layer.end*pitch}:{}),...(layer.steps?{steps:layer.steps.map(f=>f*pitch)}:{})}))};
}

return {effects,effectRecipe};},
"audio/synth.mjs":()=>{
// Original sample-free synthesis. This module runs unchanged in Node and browsers.
// Recipes contain only oscillators, filtered noise, envelopes and event times.
const SAMPLE_RATE = 44100;

function random(seed = 1) {
  let n = seed >>> 0 || 1;
  return () => { n ^= n << 13; n ^= n >>> 17; n ^= n << 5; return (n >>> 0) / 4294967296; };
}

function blep(t, dt) {
  if (t < dt) { t /= dt; return t + t - t * t - 1; }
  if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; }
  return 0;
}

function oscillator(phase, dt, wave) {
  const p = phase % 1;
  if (wave === 'triangle') return 1 - 4 * Math.abs(p - 0.5);
  if (wave === 'pulse') return (p < 0.25 ? 1 : -1 / 3) + (blep(p, dt) - blep((p + 0.75) % 1, dt)) * 2 / 3;
  if (wave === 'square') return (p < 0.5 ? 1 : -1) + blep(p, dt) - blep((p + 0.5) % 1, dt);
  return Math.sin(phase * Math.PI * 2);
}

function renderRecipe(recipe, seed = 1, sampleRate = SAMPLE_RATE) {
  const out = new Float32Array(Math.ceil(recipe.duration * sampleRate));
  recipe.layers.forEach((layer, index) => {
    const rng = random((seed + Math.imul(index + 1, 2654435761)) >>> 0);
    const start = Math.round((layer.at || 0) * sampleRate);
    const length = Math.ceil(layer.duration * sampleRate);
    const attack = layer.attack ?? 0.002;
    const release = Math.min(layer.release ?? 0.015, layer.duration / 3);
    const decay = layer.decay ?? layer.duration / 4;
    const freq = layer.freq || 440, end = layer.end ?? freq;
    let phase = 0, low = 0, slow = 0, held = 0;
    for (let i = 0; i < length && start + i < out.length; i++) {
      const t = i / sampleRate, u = t / layer.duration;
      let f = freq * Math.pow(end / freq, u);
      if (layer.steps) f = layer.steps[Math.min(layer.steps.length - 1, Math.floor(u * layer.steps.length))];
      f *= 1 + (layer.wobble || 0) * Math.sin(t * Math.PI * 2 * (layer.wobbleHz || 18)) * Math.exp(-t * 5);
      f = Math.max(15, Math.min(sampleRate * 0.2, f));
      const dt = f / sampleRate;
      phase += dt;
      let value;
      if (layer.wave === 'noise') {
        if (i % (layer.hold || 1) === 0) held = rng() * 2 - 1;
        value = held;
      } else value = oscillator(phase, dt, layer.wave);
      const cutoff = (layer.lowpass || sampleRate * 0.42) * Math.pow(layer.filterEnd ?? 1, u);
      const alpha = 1 - Math.exp(-2 * Math.PI * Math.min(cutoff, sampleRate * 0.45) / sampleRate);
      low += alpha * (value - low);
      value = low;
      if (layer.highpass) {
        slow += (1 - Math.exp(-2 * Math.PI * layer.highpass / sampleRate)) * (value - slow);
        value -= slow;
      }
      const env = Math.min(1, t / Math.max(attack, 1 / sampleRate))
        * Math.exp(-t / decay)
        * Math.min(1, Math.max(0, (layer.duration - t) / release));
      out[start + i] += value * env * layer.amp;
    }
  });
  // A shared output stage preserves relative effect levels; no per-clip normalization.
  let previousIn = 0, previousOut = 0;
  const dc = Math.exp(-2 * Math.PI * 20 / sampleRate);
  for (let i = 0; i < out.length; i++) {
    const x = out[i];
    const y = x - previousIn + dc * previousOut;
    previousIn = x; previousOut = y;
    const fade = Math.min(1, i / (sampleRate * 0.001), (out.length - 1 - i) / (sampleRate * 0.012));
    out[i] = Math.tanh(y * 1.15) * 0.70 * Math.max(0, fade);
  }
  return out;
}

function renderSequence(events, presets, duration, seed = 17, sampleRate = SAMPLE_RATE) {
  const out = new Float32Array(Math.ceil(duration * sampleRate));
  for (let k = 0; k < events.length; k++) {
    const event = events[k];
    const clip = renderRecipe(presets[event.effect], seed + k * 101, sampleRate);
    const start = Math.round(event.at * sampleRate);
    for (let i = 0; i < clip.length && start + i < out.length; i++) out[start + i] += clip[i] * (event.gain ?? 1);
  }
  // Only attenuate if necessary. Never boost a quiet event into a loud one.
  let peak = 0;
  for (const x of out) peak = Math.max(peak, Math.abs(x));
  if (peak > 0.80) for (let i = 0; i < out.length; i++) out[i] *= 0.80 / peak;
  const fade = Math.round(sampleRate * 0.015);
  for (let i = 0; i < Math.min(fade, out.length); i++) out[out.length - 1 - i] *= i / fade;
  return out;
}

return {SAMPLE_RATE,random,renderRecipe,renderSequence};},
"bank.mjs":()=>{
const {catalog,getAsset}=load("catalog.mjs");
const {renderVariation}=load("visual/renderer.mjs");
const {syncKeyboard}=load("keyboard.mjs");
const {composeScore,cycleHasSound}=load("score.mjs");
const {effectRecipe}=load("audio/effects.mjs");
const {renderRecipe}=load("audio/synth.mjs");
const {renderNeedsYou}=load("needs-you.mjs");
const {renderStateScene,stateScore}=load("state-art.mjs");
const {quietMix,routineEvents}=load("quiet-mix.mjs");
const {renderMoodScene,moodScore}=load("mood-art.mjs");
function makeScene(id){
  const asset=getAsset(id);
  if(asset.renderer==='mood-v4')return {asset,svg:renderMoodScene(asset),score:quietMix(asset,moodScore(asset))};
  if(asset.renderer==='state-v3')return {asset,svg:renderStateScene(asset),score:quietMix(asset,stateScore(asset))};
  const svg=asset.state==='needs_you'?renderNeedsYou(asset):syncKeyboard(renderVariation(asset.mood,asset.state,asset.variation,asset.name),asset);
  return {asset,svg,score:quietMix(asset,composeScore(asset,svg))};
}
function cueSeed(effect,seed=53){let h=seed>>>0;for(const c of effect)h=Math.imul(h^c.charCodeAt(0),16777619)>>>0;return h;}
function synthesizeCue(event,seed=53,sampleRate=44100){return renderRecipe(effectRecipe(event.effect,event.pitch),cueSeed(event.effect,seed),sampleRate);}
function sceneEvents(scene,{cycle=0,seed=53}={}){return routineEvents(scene.score,cycle,seed);}
// Finite PCM is generated only on demand. This helper is for tests/offline use;
// the browser player schedules individual cached cues instead of a full bank.
function renderSceneAudio(scene,{cycles=1,seed=53,sampleRate=44100}={}){
  if(!Number.isInteger(cycles)||cycles<1||cycles>3)throw new Error('Finite rendering supports 1–3 cycles');
  if(!Number.isInteger(sampleRate)||sampleRate<8000||sampleRate>96000)throw new Error('Invalid sample rate');
  const duration=scene.asset.seconds*cycles+scene.score.tailSeconds+.03;
  const output=new Float32Array(Math.ceil(duration*sampleRate)),cache=new Map();
  for(let cycle=0;cycle<cycles;cycle++)if(cycleHasSound(scene.score,cycle))for(const event of sceneEvents(scene,{cycle,seed})){
    const key=event.effect+':'+event.pitch;
    if(!cache.has(key))cache.set(key,synthesizeCue(event,seed,sampleRate));
    const clip=cache.get(key),start=Math.round((cycle*scene.asset.seconds+event.at)*sampleRate);
    for(let i=0;i<clip.length&&start+i<output.length;i++)output[start+i]+=clip[i]*event.gain*.9;
  }
  return output;
}
function chooseVariation(pair,{previousId=null,random=Math.random,hostContext={}}={}){
  let state=pair.state;
  if(state==='task_complete'&&!hostContext.completionOutcome)state='reply_ready';
  if(pair.state==='task_complete'&&hostContext.completionOutcome&&!['success','failure'].includes(hostContext.completionOutcome))throw new Error('Invalid task completion outcome');
  if(state==='starting'&&hostContext.startContext&&!['new_task','session','continuation','compacted'].includes(hostContext.startContext))throw new Error('Invalid start context');
  const list=catalog.filter(a=>a.mood===pair.mood&&a.state===state&&
    (state!=='task_complete'||a.outcome===hostContext.completionOutcome)&&
    (state!=='starting'||a.startContext===(hostContext.startContext||'session')));
  if(!list.length)throw new Error('Invalid mood/state pair');
  const choices=list.filter(a=>a.id!==previousId);
  const draw=Math.max(0,Math.min(.999999,Number(random())||0));
  return (choices.length?choices:list)[Math.floor(draw*(choices.length||list.length))].id;
}

return {makeScene,cueSeed,synthesizeCue,sceneEvents,renderSceneAudio,chooseVariation};},
"catalog.mjs":()=>{
const {catalog:legacyCatalog}=load("legacy-catalog.mjs");
const {moodAdditions,newMoods}=load("mood-catalog.mjs");
const moods=['happy','excited','proud','curious','determined','grumpy','sad',...newMoods];
const catalog=[...legacyCatalog,...moodAdditions];
function getAsset(id){const asset=catalog.find(a=>a.id===id);if(!asset)throw new Error('Unknown Boop variation: '+id);return asset;}

return {moods,catalog,getAsset};},
"keyboard.mjs":()=>{
// One key plan controls the visual flashes and sound down/up strokes.
const keyPlans={
  steady:{presses:Array.from({length:16},(_,i)=>Number((.05+i*.15).toFixed(6))),hold:.045},
  'key-rain':{presses:Array.from({length:6},(_,i)=>Number((.15+i*.30).toFixed(6))),hold:.07},
  flood:{presses:Array.from({length:20},(_,i)=>Number((.08+i*.32).toFixed(6))),hold:.07},
  turbo:{presses:Array.from({length:16},(_,i)=>Number((.05+i*.10).toFixed(6))),hold:.025}
};
function syncKeyboard(svg,asset){
  const plan=keyPlans[asset.action];if(!plan)return svg;let tracks=0;
  const revised=svg.replace(/<g([^>]*)>(<animate\s[^>]+\/>)(<rect\s[^>]+\/>)/g,(full,group,anim,rect)=>{
    const attrs=Object.fromEntries([...rect.matchAll(/([\w:-]+)="([^"]*)"/g)].map(m=>[m[1],m[2]]));
    if(![176,185].includes(Number(attrs.y))||Number(attrs.width)!==10||Number(attrs.height)!==4||attrs.fill!=='#F8F7EF')return full;
    const column=(Number(attrs.x)-90)/14;if(!Number.isInteger(column)||column<0||column>9)return full;
    const points=[[0,0]];
    plan.presses.forEach((t,i)=>{if(i%2===column%2)points.push([t,1],[t+plan.hold,0]);});
    points.push([asset.seconds,0]);points.sort((a,b)=>a[0]-b[0]);tracks++;
    const tag=`<animate attributeName="opacity" values="${points.map(p=>p[1]).join(';')}" keyTimes="${points.map(p=>Number((p[0]/asset.seconds).toFixed(9))).join(';')}" dur="${asset.seconds}s" begin="0s" repeatCount="indefinite" calcMode="discrete" fill="freeze" data-audio-sync="key-press"/>`;
    return `<g${group.replace(/opacity="[^"]*"/,'opacity="0"')}>${tag}${rect}`;
  });
  if(tracks!==7)throw new Error(`Expected 7 keyboard tracks for ${asset.id}; found ${tracks}`);
  return revised;
}

return {keyPlans,syncKeyboard};},
"legacy-catalog.mjs":()=>{
const {requestPerformance}=load("request-performances.mjs");
const {additions}=load("state-catalog.mjs");
// Compact variation index; descriptive historical catalogs are not needed at runtime.
const catalog = [{"id":"happy.working.01","mood":"happy","state":"working","variation":1,"name":"Cheerful conveyor","action":"conveyor","caption":"Hop little parcels into the inbox","seconds":5},{"id":"happy.working.02","mood":"happy","state":"working","variation":2,"name":"Work-song piano","action":"piano","caption":"Play the keys like a tiny piano","seconds":4},{"id":"happy.working.03","mood":"happy","state":"working","variation":3,"name":"Paper-plane post","action":"paper-plane","caption":"Fold a page, then send it sailing","seconds":5},{"id":"happy.working.04","mood":"happy","state":"working","variation":4,"name":"Happy little builder","action":"block-tower","caption":"Stack bright cubes into a tower","seconds":5},{"id":"happy.working.05","mood":"happy","state":"working","variation":5,"name":"Stamp-dance","action":"stamp","caption":"Bounce a giant stamp onto a card","seconds":4},{"id":"happy.needs_you.01","mood":"happy","state":"needs_you","variation":1,"name":"Knock-and-reveal panel","action":"alert-knock","caption":"Knock knock → ding + request panel","seconds":6},{"id":"happy.needs_you.02","mood":"happy","state":"needs_you","variation":2,"name":"Large warning card","action":"alert-card","caption":"Knock knock → ding + warning card","seconds":7.2},{"id":"happy.needs_you.03","mood":"happy","state":"needs_you","variation":3,"name":"Oversized ringing bell","action":"alert-bell","caption":"Knock knock → ding + bell reveal","seconds":6.4},{"id":"happy.task_complete.01","mood":"happy","state":"task_complete","variation":1,"name":"Trophy fireworks","action":null,"caption":"Cup entrance + a square-confetti fountain","seconds":6.4},{"id":"happy.task_complete.02","mood":"happy","state":"task_complete","variation":2,"name":"Curtain-call reveal","action":null,"caption":"Curtains open onto the result","seconds":7.2},{"id":"happy.task_complete.03","mood":"happy","state":"task_complete","variation":3,"name":"Onto the podium","action":null,"caption":"A stepped podium rises under the cup","seconds":6.4},{"id":"happy.listening.01","mood":"happy","state":"listening","variation":1,"name":"Focused attention","action":null,"caption":"Four large focus corners frame the face","seconds":6.4},{"id":"happy.listening.02","mood":"happy","state":"listening","variation":2,"name":"Headphones on","action":null,"caption":"A pixel headset settles around the face","seconds":7.2},{"id":"happy.listening.03","mood":"happy","state":"listening","variation":3,"name":"The listening trumpet","action":null,"caption":"Lean toward a comically large ear trumpet","seconds":6.8},{"id":"happy.idle.01","mood":"happy","state":"idle","variation":1,"name":"Quiet blink","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":8},{"id":"happy.idle.02","mood":"happy","state":"idle","variation":2,"name":"Small look-around","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":10},{"id":"happy.idle.03","mood":"happy","state":"idle","variation":3,"name":"Tiny resting stretch","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":9},{"id":"happy.asleep.01","mood":"happy","state":"asleep","variation":1,"name":"Even sleep","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"happy.asleep.02","mood":"happy","state":"asleep","variation":2,"name":"Small dream twitch","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"happy.asleep.03","mood":"happy","state":"asleep","variation":3,"name":"Sleepy resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"happy.no_app.01","mood":"happy","state":"no_app","variation":1,"name":"Disconnected doze","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"happy.no_app.02","mood":"happy","state":"no_app","variation":2,"name":"Disconnected blink","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"happy.no_app.03","mood":"happy","state":"no_app","variation":3,"name":"Disconnected resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"excited.working.01","mood":"excited","state":"working","variation":1,"name":"Turbo keyboard","action":"turbo","caption":"Pound the keys in a frantic flurry","seconds":1.6},{"id":"excited.working.02","mood":"excited","state":"working","variation":2,"name":"Too many ideas","action":"juggle","caption":"Juggle three work cubes overhead","seconds":3},{"id":"excited.working.03","mood":"excited","state":"working","variation":3,"name":"Keyboard liftoff","action":"rocket","caption":"A rocket keyboard lifts on square flames","seconds":4},{"id":"excited.working.04","mood":"excited","state":"working","variation":4,"name":"Task treadmill","action":"treadmill","caption":"Cards race past on a roller belt","seconds":3.6},{"id":"excited.working.05","mood":"excited","state":"working","variation":5,"name":"Pinball brain","action":"pinball","caption":"A bright cube ricochets among bumpers","seconds":3},{"id":"excited.needs_you.01","mood":"excited","state":"needs_you","variation":1,"name":"Knock-and-reveal panel","action":"alert-knock","caption":"Knock knock → ding + request panel","seconds":6},{"id":"excited.needs_you.02","mood":"excited","state":"needs_you","variation":2,"name":"Large warning card","action":"alert-card","caption":"Knock knock → ding + warning card","seconds":7.2},{"id":"excited.needs_you.03","mood":"excited","state":"needs_you","variation":3,"name":"Oversized ringing bell","action":"alert-bell","caption":"Knock knock → ding + bell reveal","seconds":6.4},{"id":"excited.task_complete.01","mood":"excited","state":"task_complete","variation":1,"name":"Trophy fireworks","action":null,"caption":"Cup entrance + a square-confetti fountain","seconds":6.4},{"id":"excited.task_complete.02","mood":"excited","state":"task_complete","variation":2,"name":"Curtain-call reveal","action":null,"caption":"Curtains open onto the result","seconds":7.2},{"id":"excited.task_complete.03","mood":"excited","state":"task_complete","variation":3,"name":"Onto the podium","action":null,"caption":"A stepped podium rises under the cup","seconds":6.4},{"id":"excited.listening.01","mood":"excited","state":"listening","variation":1,"name":"Focused attention","action":null,"caption":"Four large focus corners frame the face","seconds":6.4},{"id":"excited.listening.02","mood":"excited","state":"listening","variation":2,"name":"Headphones on","action":null,"caption":"A pixel headset settles around the face","seconds":7.2},{"id":"excited.listening.03","mood":"excited","state":"listening","variation":3,"name":"The listening trumpet","action":null,"caption":"Lean toward a comically large ear trumpet","seconds":6.8},{"id":"excited.idle.01","mood":"excited","state":"idle","variation":1,"name":"Quiet blink","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":8},{"id":"excited.idle.02","mood":"excited","state":"idle","variation":2,"name":"Small look-around","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":10},{"id":"excited.idle.03","mood":"excited","state":"idle","variation":3,"name":"Tiny resting stretch","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":9},{"id":"excited.asleep.01","mood":"excited","state":"asleep","variation":1,"name":"Even sleep","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"excited.asleep.02","mood":"excited","state":"asleep","variation":2,"name":"Small dream twitch","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"excited.asleep.03","mood":"excited","state":"asleep","variation":3,"name":"Sleepy resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"excited.no_app.01","mood":"excited","state":"no_app","variation":1,"name":"Disconnected doze","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"excited.no_app.02","mood":"excited","state":"no_app","variation":2,"name":"Disconnected blink","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"excited.no_app.03","mood":"excited","state":"no_app","variation":3,"name":"Disconnected resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"proud.working.01","mood":"proud","state":"working","variation":1,"name":"The grand workstation","action":"pedestal","caption":"A desk rises on a show-off pedestal","seconds":5},{"id":"proud.working.02","mood":"proud","state":"working","variation":2,"name":"Maestro of the tabs","action":"conductor","caption":"A baton conducts an orbit of cards","seconds":4},{"id":"proud.working.03","mood":"proud","state":"working","variation":3,"name":"Effortless origami","action":"origami","caption":"Fold a plain sheet into a pixel crane","seconds":5},{"id":"proud.working.04","mood":"proud","state":"working","variation":4,"name":"Polish the masterpiece","action":"polish","caption":"Buff one work tile to a ridiculous shine","seconds":4.5},{"id":"proud.working.05","mood":"proud","state":"working","variation":5,"name":"One-key virtuoso","action":"one-key","caption":"Perform an absurd flourish on one giant key","seconds":4},{"id":"proud.needs_you.01","mood":"proud","state":"needs_you","variation":1,"name":"Knock-and-reveal panel","action":"alert-knock","caption":"Knock knock → ding + request panel","seconds":6},{"id":"proud.needs_you.02","mood":"proud","state":"needs_you","variation":2,"name":"Large warning card","action":"alert-card","caption":"Knock knock → ding + warning card","seconds":7.2},{"id":"proud.needs_you.03","mood":"proud","state":"needs_you","variation":3,"name":"Oversized ringing bell","action":"alert-bell","caption":"Knock knock → ding + bell reveal","seconds":6.4},{"id":"proud.task_complete.01","mood":"proud","state":"task_complete","variation":1,"name":"Trophy fireworks","action":null,"caption":"Cup entrance + a square-confetti fountain","seconds":6.4},{"id":"proud.task_complete.02","mood":"proud","state":"task_complete","variation":2,"name":"MWHAHAHA!","action":null,"caption":"Curtains open · MWHAHAHA grows in four steps","seconds":7.2},{"id":"proud.task_complete.03","mood":"proud","state":"task_complete","variation":3,"name":"Onto the podium","action":null,"caption":"A stepped podium rises under the cup","seconds":6.4},{"id":"proud.listening.01","mood":"proud","state":"listening","variation":1,"name":"Focused attention","action":null,"caption":"Four large focus corners frame the face","seconds":6.4},{"id":"proud.listening.02","mood":"proud","state":"listening","variation":2,"name":"Headphones on","action":null,"caption":"A pixel headset settles around the face","seconds":7.2},{"id":"proud.listening.03","mood":"proud","state":"listening","variation":3,"name":"The listening trumpet","action":null,"caption":"Lean toward a comically large ear trumpet","seconds":6.8},{"id":"proud.idle.01","mood":"proud","state":"idle","variation":1,"name":"Quiet blink","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":8},{"id":"proud.idle.02","mood":"proud","state":"idle","variation":2,"name":"Small look-around","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":10},{"id":"proud.idle.03","mood":"proud","state":"idle","variation":3,"name":"Tiny resting stretch","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":9},{"id":"proud.asleep.01","mood":"proud","state":"asleep","variation":1,"name":"Even sleep","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"proud.asleep.02","mood":"proud","state":"asleep","variation":2,"name":"Small dream twitch","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"proud.asleep.03","mood":"proud","state":"asleep","variation":3,"name":"Sleepy resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"proud.no_app.01","mood":"proud","state":"no_app","variation":1,"name":"Disconnected doze","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"proud.no_app.02","mood":"proud","state":"no_app","variation":2,"name":"Disconnected blink","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"proud.no_app.03","mood":"proud","state":"no_app","variation":3,"name":"Disconnected resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"curious.working.01","mood":"curious","state":"working","variation":1,"name":"Under the lens","action":"magnifier","caption":"A giant lens inspects a little specimen","seconds":5},{"id":"curious.working.02","mood":"curious","state":"working","variation":2,"name":"What is over there?","action":"periscope","caption":"Extend a periscope, then pivot its eye","seconds":5},{"id":"curious.working.03","mood":"curious","state":"working","variation":3,"name":"How does this work?","action":"explode","caption":"Pull a cube apart and rebuild it","seconds":5},{"id":"curious.working.04","mood":"curious","state":"working","variation":4,"name":"Follow the maze","action":"maze","caption":"Chase a wandering square through a maze","seconds":5},{"id":"curious.working.05","mood":"curious","state":"working","variation":5,"name":"Mystery-box inspection","action":"box","caption":"Lift the lid and peer into the box","seconds":5},{"id":"curious.needs_you.01","mood":"curious","state":"needs_you","variation":1,"name":"Knock-and-reveal panel","action":"alert-knock","caption":"Knock knock → ding + request panel","seconds":6},{"id":"curious.needs_you.02","mood":"curious","state":"needs_you","variation":2,"name":"Large warning card","action":"alert-card","caption":"Knock knock → ding + warning card","seconds":7.2},{"id":"curious.needs_you.03","mood":"curious","state":"needs_you","variation":3,"name":"Oversized ringing bell","action":"alert-bell","caption":"Knock knock → ding + bell reveal","seconds":6.4},{"id":"curious.task_complete.01","mood":"curious","state":"task_complete","variation":1,"name":"Trophy fireworks","action":null,"caption":"Cup entrance + a square-confetti fountain","seconds":6.4},{"id":"curious.task_complete.02","mood":"curious","state":"task_complete","variation":2,"name":"Curtain-call reveal","action":null,"caption":"Curtains open onto the result","seconds":7.2},{"id":"curious.task_complete.03","mood":"curious","state":"task_complete","variation":3,"name":"Onto the podium","action":null,"caption":"A stepped podium rises under the cup","seconds":6.4},{"id":"curious.listening.01","mood":"curious","state":"listening","variation":1,"name":"Focused attention","action":null,"caption":"Four large focus corners frame the face","seconds":6.4},{"id":"curious.listening.02","mood":"curious","state":"listening","variation":2,"name":"Headphones on","action":null,"caption":"A pixel headset settles around the face","seconds":7.2},{"id":"curious.listening.03","mood":"curious","state":"listening","variation":3,"name":"The listening trumpet","action":null,"caption":"Lean toward a comically large ear trumpet","seconds":6.8},{"id":"curious.idle.01","mood":"curious","state":"idle","variation":1,"name":"Quiet blink","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":8},{"id":"curious.idle.02","mood":"curious","state":"idle","variation":2,"name":"Small look-around","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":10},{"id":"curious.idle.03","mood":"curious","state":"idle","variation":3,"name":"Tiny resting stretch","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":9},{"id":"curious.asleep.01","mood":"curious","state":"asleep","variation":1,"name":"Even sleep","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"curious.asleep.02","mood":"curious","state":"asleep","variation":2,"name":"Small dream twitch","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"curious.asleep.03","mood":"curious","state":"asleep","variation":3,"name":"Sleepy resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"curious.no_app.01","mood":"curious","state":"no_app","variation":1,"name":"Disconnected doze","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"curious.no_app.02","mood":"curious","state":"no_app","variation":2,"name":"Disconnected blink","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"curious.no_app.03","mood":"curious","state":"no_app","variation":3,"name":"Disconnected resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"determined.working.01","mood":"determined","state":"working","variation":1,"name":"Steady typing","action":"steady","caption":"A planted, deliberate keyboard rhythm","seconds":2.4},{"id":"determined.working.02","mood":"determined","state":"working","variation":2,"name":"One more push","action":"uphill","caption":"Shove a heavy cube up stepped ground","seconds":5},{"id":"determined.working.03","mood":"determined","state":"working","variation":3,"name":"Brick by brick","action":"brick-wall","caption":"Build a wall one block at a time","seconds":5},{"id":"determined.working.04","mood":"determined","state":"working","variation":4,"name":"Haul the workload","action":"winch","caption":"Crank a pulley to lift a heavy stack","seconds":5},{"id":"determined.working.05","mood":"determined","state":"working","variation":5,"name":"Cut through the tangle","action":"scissors","caption":"Giant scissors snip a knotted strip","seconds":4},{"id":"determined.needs_you.01","mood":"determined","state":"needs_you","variation":1,"name":"Knock-and-reveal panel","action":"alert-knock","caption":"Knock knock → ding + request panel","seconds":6},{"id":"determined.needs_you.02","mood":"determined","state":"needs_you","variation":2,"name":"Large warning card","action":"alert-card","caption":"Knock knock → ding + warning card","seconds":7.2},{"id":"determined.needs_you.03","mood":"determined","state":"needs_you","variation":3,"name":"Oversized ringing bell","action":"alert-bell","caption":"Knock knock → ding + bell reveal","seconds":6.4},{"id":"determined.task_complete.01","mood":"determined","state":"task_complete","variation":1,"name":"Trophy fireworks","action":null,"caption":"Cup entrance + a square-confetti fountain","seconds":6.4},{"id":"determined.task_complete.02","mood":"determined","state":"task_complete","variation":2,"name":"Curtain-call reveal","action":null,"caption":"Curtains open onto the result","seconds":7.2},{"id":"determined.task_complete.03","mood":"determined","state":"task_complete","variation":3,"name":"Onto the podium","action":null,"caption":"A stepped podium rises under the cup","seconds":6.4},{"id":"determined.listening.01","mood":"determined","state":"listening","variation":1,"name":"Focused attention","action":null,"caption":"Four large focus corners frame the face","seconds":6.4},{"id":"determined.listening.02","mood":"determined","state":"listening","variation":2,"name":"Headphones on","action":null,"caption":"A pixel headset settles around the face","seconds":7.2},{"id":"determined.listening.03","mood":"determined","state":"listening","variation":3,"name":"The listening trumpet","action":null,"caption":"Lean toward a comically large ear trumpet","seconds":6.8},{"id":"determined.idle.01","mood":"determined","state":"idle","variation":1,"name":"Quiet blink","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":8},{"id":"determined.idle.02","mood":"determined","state":"idle","variation":2,"name":"Small look-around","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":10},{"id":"determined.idle.03","mood":"determined","state":"idle","variation":3,"name":"Tiny resting stretch","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":9},{"id":"determined.asleep.01","mood":"determined","state":"asleep","variation":1,"name":"Even sleep","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"determined.asleep.02","mood":"determined","state":"asleep","variation":2,"name":"Small dream twitch","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"determined.asleep.03","mood":"determined","state":"asleep","variation":3,"name":"Sleepy resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"determined.no_app.01","mood":"determined","state":"no_app","variation":1,"name":"Disconnected doze","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"determined.no_app.02","mood":"determined","state":"no_app","variation":2,"name":"Disconnected blink","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"determined.no_app.03","mood":"determined","state":"no_app","variation":3,"name":"Disconnected resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"grumpy.working.01","mood":"grumpy","state":"working","variation":1,"name":"Keyboard meltdown","action":"key-rain","caption":"Spray keycaps in every direction","seconds":1.8},{"id":"grumpy.working.02","mood":"grumpy","state":"working","variation":2,"name":"Bash, bash, SNAP!","action":"snap","caption":"Three accelerating desk slams → snap → scatter","seconds":3.2},{"id":"grumpy.working.03","mood":"grumpy","state":"working","variation":3,"name":"Smash the fourth wall","action":"throw","caption":"Desk hit → three screen hits → cracks → throw","seconds":4.4},{"id":"grumpy.working.04","mood":"grumpy","state":"working","variation":4,"name":"Paper rage, rapid-fire","action":"crumple","caption":"Crumple and fling three pages: right, left, right","seconds":2.7},{"id":"grumpy.working.05","mood":"grumpy","state":"working","variation":5,"name":"Pressure cooker","action":"boiler","caption":"Frantic lid rattle → two steam bursts → lid launch","seconds":2.4},{"id":"grumpy.needs_you.01","mood":"grumpy","state":"needs_you","variation":1,"name":"Knock-and-reveal panel","action":"alert-knock","caption":"Knock knock → ding + request panel","seconds":6},{"id":"grumpy.needs_you.02","mood":"grumpy","state":"needs_you","variation":2,"name":"Large warning card","action":"alert-card","caption":"Knock knock → ding + warning card","seconds":7.2},{"id":"grumpy.needs_you.03","mood":"grumpy","state":"needs_you","variation":3,"name":"Oversized ringing bell","action":"alert-bell","caption":"Knock knock → ding + bell reveal","seconds":6.4},{"id":"grumpy.task_complete.01","mood":"grumpy","state":"task_complete","variation":1,"name":"Trophy fireworks","action":null,"caption":"Cup entrance + a square-confetti fountain","seconds":6.4},{"id":"grumpy.task_complete.02","mood":"grumpy","state":"task_complete","variation":2,"name":"Curtain-call reveal","action":null,"caption":"Curtains open onto the result","seconds":7.2},{"id":"grumpy.task_complete.03","mood":"grumpy","state":"task_complete","variation":3,"name":"Onto the podium","action":null,"caption":"A stepped podium rises under the cup","seconds":6.4},{"id":"grumpy.listening.01","mood":"grumpy","state":"listening","variation":1,"name":"Focused attention","action":null,"caption":"Four large focus corners frame the face","seconds":6.4},{"id":"grumpy.listening.02","mood":"grumpy","state":"listening","variation":2,"name":"Headphones on","action":null,"caption":"A pixel headset settles around the face","seconds":7.2},{"id":"grumpy.listening.03","mood":"grumpy","state":"listening","variation":3,"name":"The listening trumpet","action":null,"caption":"Lean toward a comically large ear trumpet","seconds":6.8},{"id":"grumpy.idle.01","mood":"grumpy","state":"idle","variation":1,"name":"Quiet blink","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":8},{"id":"grumpy.idle.02","mood":"grumpy","state":"idle","variation":2,"name":"Small look-around","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":10},{"id":"grumpy.idle.03","mood":"grumpy","state":"idle","variation":3,"name":"Tiny resting stretch","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":9},{"id":"grumpy.asleep.01","mood":"grumpy","state":"asleep","variation":1,"name":"Even sleep","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"grumpy.asleep.02","mood":"grumpy","state":"asleep","variation":2,"name":"Small dream twitch","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"grumpy.asleep.03","mood":"grumpy","state":"asleep","variation":3,"name":"Sleepy resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"grumpy.no_app.01","mood":"grumpy","state":"no_app","variation":1,"name":"Disconnected doze","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"grumpy.no_app.02","mood":"grumpy","state":"no_app","variation":2,"name":"Disconnected blink","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"grumpy.no_app.03","mood":"grumpy","state":"no_app","variation":3,"name":"Disconnected resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"sad.working.01","mood":"sad","state":"working","variation":1,"name":"Typing through a flood","action":"flood","caption":"Cube tears submerge the keyboard","seconds":6.4},{"id":"sad.working.02","mood":"sad","state":"working","variation":2,"name":"Bucket brigade","action":"buckets","caption":"Catch the tears; the buckets overflow","seconds":5},{"id":"sad.working.03","mood":"sad","state":"working","variation":3,"name":"Never-ending tissue","action":"tissue","caption":"A printer dispenses an accordion of tissue","seconds":5},{"id":"sad.working.04","mood":"sad","state":"working","variation":4,"name":"Rainy-day workstation","action":"umbrella","caption":"Shelter the work under a little umbrella","seconds":5},{"id":"sad.working.05","mood":"sad","state":"working","variation":5,"name":"Keep the work afloat","action":"raft","caption":"A work raft bobs on a sea of blue cubes","seconds":5},{"id":"sad.needs_you.01","mood":"sad","state":"needs_you","variation":1,"name":"Knock-and-reveal panel","action":"alert-knock","caption":"Knock knock → ding + request panel","seconds":6},{"id":"sad.needs_you.02","mood":"sad","state":"needs_you","variation":2,"name":"Large warning card","action":"alert-card","caption":"Knock knock → ding + warning card","seconds":7.2},{"id":"sad.needs_you.03","mood":"sad","state":"needs_you","variation":3,"name":"Oversized ringing bell","action":"alert-bell","caption":"Knock knock → ding + bell reveal","seconds":6.4},{"id":"sad.task_complete.01","mood":"sad","state":"task_complete","variation":1,"name":"Trophy fireworks","action":null,"caption":"Cup entrance + a square-confetti fountain","seconds":6.4},{"id":"sad.task_complete.02","mood":"sad","state":"task_complete","variation":2,"name":"Curtain-call reveal","action":null,"caption":"Curtains open onto the result","seconds":7.2},{"id":"sad.task_complete.03","mood":"sad","state":"task_complete","variation":3,"name":"Onto the podium","action":null,"caption":"A stepped podium rises under the cup","seconds":6.4},{"id":"sad.listening.01","mood":"sad","state":"listening","variation":1,"name":"Focused attention","action":null,"caption":"Four large focus corners frame the face","seconds":6.4},{"id":"sad.listening.02","mood":"sad","state":"listening","variation":2,"name":"Headphones on","action":null,"caption":"A pixel headset settles around the face","seconds":7.2},{"id":"sad.listening.03","mood":"sad","state":"listening","variation":3,"name":"The listening trumpet","action":null,"caption":"Lean toward a comically large ear trumpet","seconds":6.8},{"id":"sad.idle.01","mood":"sad","state":"idle","variation":1,"name":"Quiet blink","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":8},{"id":"sad.idle.02","mood":"sad","state":"idle","variation":2,"name":"Small look-around","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":10},{"id":"sad.idle.03","mood":"sad","state":"idle","variation":3,"name":"Tiny resting stretch","action":null,"caption":"Shared quiet motion · mood-specific face","seconds":9},{"id":"sad.asleep.01","mood":"sad","state":"asleep","variation":1,"name":"Even sleep","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"sad.asleep.02","mood":"sad","state":"asleep","variation":2,"name":"Small dream twitch","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"sad.asleep.03","mood":"sad","state":"asleep","variation":3,"name":"Sleepy resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12},{"id":"sad.no_app.01","mood":"sad","state":"no_app","variation":1,"name":"Disconnected doze","action":null,"caption":"Shared quiet routine · mood ignored","seconds":9},{"id":"sad.no_app.02","mood":"sad","state":"no_app","variation":2,"name":"Disconnected blink","action":null,"caption":"Shared quiet routine · mood ignored","seconds":10},{"id":"sad.no_app.03","mood":"sad","state":"no_app","variation":3,"name":"Disconnected resettle","action":null,"caption":"Shared quiet routine · mood ignored","seconds":12}];
function getAsset(id){const asset=catalog.find(a=>a.id===id);if(!asset)throw new Error('Unknown Boop variation: '+id);return asset;}
for(const asset of catalog)if(asset.state==='task_complete')asset.outcome='success';
catalog.push(...additions);
for(const asset of catalog){if(asset.state==='needs_you'){const p=requestPerformance(asset);asset.name=p.name;asset.action='request-'+p.kind;asset.caption=p.story;}}

return {catalog,getAsset};},
"mood-art.mjs":()=>{
const {palette:P,rect,path,group,at,star,keycap}=load("visual/base.mjs");
const {pixelText}=load("state-art.mjs");
const {moodProfiles}=load("mood-catalog.mjs");
const {sustainedStates}=load("state-catalog.mjs");
const {effects}=load("audio/effects.mjs");
const {protectedSoundStates}=load("quiet-mix.mjs");
const green='#83D99A',deep='#244634',amberDark='#352915';
const round=x=>Number(x.toFixed(6));
const safe=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const text=(s,x,y,k=2,c=P.ink)=>pixelText(s,x,y,k,c);
const centered=(s,y,k=2,c=P.ink)=>text(s,Math.round((320-(s.length*6-1)*k)/2),y,k,c);
const slab=(x,y,w,h,c=P.ink)=>path(`M${x+4} ${y}h${w-8}v4h4v${h-8}h-4v4H${x+4}v-4h-4V${y+4}h4Z`,c);
const pad=(x,y,w=28,h=20)=>slab(x,y,w,h,P.ink);
const cube=(x,y,s=20,c=P.blue)=>rect(x,y,s,s,c)+rect(x+4,y+4,s-8,4,P.ink)+rect(x+s-4,y+4,4,s-4,P.dim);
const card=(s,y=155,c=P.blue)=>{const w=Math.max(112,(s.length*6-1)*2+20);return slab((320-w)/2,y,w,30,c)+centered(s,y+8,2,P.black);};
const held=(s,y=155,c=P.blue)=>card(s,y,c)+pad(74,y+11,24,16)+pad(222,y+11,24,16);
const paper=(x,y,w=42,h=32,c=P.blue,pattern=0)=>rect(x,y,w,h,P.prop)+rect(x+4,y+4,w-8,h-8,P.black)+rect(x+8,y+8,8,6,c)+rect(x+20,y+8,w-28,4,c)+rect(x+8,y+20,w-16,4,c)+(pattern?rect(x+8,y+26,12,3,P.dim):'');
const board=(x=83,y=158,w=154,press=-1)=>slab(x,y,w,28,P.dim)+rect(x+4,y+4,w-8,20,P.black)+Array.from({length:20},(_,i)=>rect(x+8+(i%10)*((w-16)/10),y+7+Math.floor(i/10)*9,Math.max(5,(w-36)/10),5,i===press%20?P.ink:P.prop)).join('');
const desk=()=>rect(45,188,230,4,P.dim);
const burst=(x,y,phase=1,c=P.prop,n=8)=>Array.from({length:n},(_,i)=>{const dx=[-1,1,-.6,.6,0,-1,1,0][i%8],dy=[-.3,-.3,-1,-1,-1,.5,.5,1][i%8],s=phase>2?4:8;return rect(Math.round(x+dx*(16+phase*9)),Math.round(y+dy*(10+phase*7)),s,s,i%3?c:P.ink);}).join('');
const lens=(x,y,c=P.blue)=>at(x,y,path('M8 0h28v8h8v28h-8v8H8v-8H0V8h8Zm4 8v4H8v20h4v4h20v-4h4V12h-4V8Z',c)+rect(34,34,8,8,c)+rect(40,40,12,12,P.prop));
const robot=(x,y,phase=0,c=P.blue,cargo=false)=>at(x,y,rect(12,-5,6,5,P.dim)+slab(0,0,32,24,c)+rect(4,5,24,12,P.black)+rect(8,8,5,5,P.ink)+rect(20,8,5,5,P.ink)+rect(5,24,22,8,P.dim)+rect(phase%2?2:5,32,8,6,c)+rect(phase%2?22:19,32,8,6,c)+(phase===3?pad(29,-5,12,12):pad(-7,20,12,12))+(cargo?cube(26,20,16,P.amber):''));
const cog=(x,y,r=28,c=P.prop,phase=0)=>at(x,y,rect(-r,-r/2,r*2,r,c)+rect(-r/2,-r,r,r*2,c)+rect(-r/2,-r/2,r,r,P.black)+rect(phase%2?-5:-r/2+4,phase%2?-r/2+4:-5,10,10,c));
const plug=(x,y,c=P.prop)=>slab(x,y,34,26,c)+rect(x+34,y+4,12,5,c)+rect(x+34,y+17,12,5,c)+rect(x-18,y+10,18,6,P.dim);
const arrow=(x,y,c=P.blue)=>rect(x,y+6,24,6,c)+path(`M${x+20} ${y}h6v6h6v6h-6v6h-6Z`,c);
const bang=(x,y,c=P.amber)=>rect(x,y,16,40,c)+rect(x,y+48,16,12,c);
const folder=(x,y,w=80,h=50,c=P.dim)=>rect(x,y,30,8,c)+slab(x,y+8,w,h,c)+rect(x+8,y+16,w-16,4,P.prop);
const cup=(x,y,s=1)=>at(x,y,group(path('M0 0h56v30h-8v12H8V30H0ZM-14 4H0v7h-7v12H4v7h-18ZM56 4h14v26H52v-7h11V11h-7ZM22 42h12v15h14v8H8v-8h14Z',P.ochre)+rect(9,4,8,22,P.ink),`transform="scale(${s})"`));
const quietStates=['no_app','asleep','idle','listening','waiting'];
const typingActions=['flow-keys','split-keys','tear-type','tissue-type','umbrella-work','cautious-key','matrix','console'];

// Every retained sound comes from one of these visible contacts. No audio-only jitter.
function moodPlan(a){
 const p=moodProfiles[a.mood],steps=[];
 const add=(t,stage,effect=null,gain=.55,extra={})=>steps.push({at:round(t),stage,effect,gain,...extra});
 if(a.state==='needs_you'){
  add(0,0);const hits=p.knocks.map((t,i)=>round(t+((a.variation-1)*.06)*(i+1)));
  hits.forEach((t,i)=>{const lead=Math.min(.13,i?(t-hits[i-1])*.30:.13),tail=Math.min(.18,i<hits.length-1?(hits[i+1]-t)*.60:.18);add(t-lead,1,null,0,{hit:i});add(t,2,'knock',p.tapGain,{hit:i});add(t+tail*.55,3,null,0,{hit:i});add(t+tail,4,null,0,{hit:i});});
  const signal=round(hits.at(-1)+.38);add(signal,5,'alertDing',.92);add(signal+.22,6);add(signal+1.08,7);add(a.seconds-.52,8);add(a.seconds-.18,0);add(a.seconds,0);
  return {steps,signal,policy:'entry',intervalSeconds:0};
 }
 const timings={calm:[0,.14,.26,.35,.46,.57,.68,.79,.93,1],engaged:[0,.09,.18,.28,.39,.50,.62,.75,.91,1],annoyed:[0,.10,.18,.34,.42,.59,.66,.80,.94,1],irritated:[0,.07,.14,.23,.29,.44,.53,.69,.89,1],whiny:[0,.13,.23,.35,.43,.59,.68,.82,.94,1],wounded:[0,.16,.23,.38,.47,.61,.69,.83,.95,1]};
 let times=[...(a.sharedQuiet?[0,.12,.23,.34,.46,.57,.68,.79,.92,1]:timings[a.mood])];
 // Different action lengths AND internal pacing: deliberate reveal, clustered work, long retreat.
 if(a.variation%3===2)times=times.map((t,i)=>i>0&&i<8?round(t*.93):t);
 if(a.variation%3===0)times=times.map((t,i)=>i>0&&i<8?round(t+(i%2?.018:-.014)):t);
 const materials={starting:['paper','fold','latch','paper','fold','slide','key','cloth'],planning:['paper','wood','slide','paper','latch','paper','fold','cloth'],terminal:['latch','key','keyB','space','keyC','key','ratchet','cloth'],tool_use:['latch','metal','latch','ratchet','ratchet','metal','slide','cloth'],searching:['slide','latch','slide','swipe','paper','paper','wood','cloth'],analyzing:['paper','slide','paper','latch','paper','wood','slide','cloth'],testing:['wood','latch','slide','wood','latch','slide','wood','cloth'],delegating:['ratchet','pop','landing','wood','wood','swipe','latch','cloth'],helper_return:['slide','landing','cloth','paper','fold','cloth','slide','cloth'],reply_ready:['paper','fold','slide','paper','latch','paper','fold','cloth'],error:['ratchet','creak','latch','snap','failedAttempt','keycap','cloth','cloth'],stopped:['brake','wood','slide','latch','paper','cloth','cloth','cloth'],poked:['cushion','rubber','cushion','cloth','rubber','cloth','cloth','cloth'],tap_spam:['cushion','cushion','cloth','cushion','rubber','cloth','cloth','cloth']};
 let sounds=materials[a.state]||['key','keyB','paper','keyC','wood','slide','key','cloth'];
 if(a.state==='working'){
  if(/paper|patch|folder|tissue|blueprint|feed|pencil|erase/.test(a.action))sounds=['paper','fold','slide','paper','snip','paper','cloth','fold'];
  if(/crank|cable|ratchet/.test(a.action))sounds=['metal','ratchet','creak','latch','ratchet','slide','latch','cloth'];
  if(/stack|garden|collect|belt|sort/.test(a.action))sounds=['wood','slide','paper','wood','latch','slide','paper','cloth'];
 }
 for(let i=0;i<times.length;i++){
  const stage=i===times.length-1?0:i;
  let effect=i>0&&i<9?sounds[i-1]:null,gain=.50;
  if(quietStates.includes(a.state))effect=null;
  if(a.state==='task_complete'){
   effect=i===4?(a.outcome==='success'?(a.variation===2?'trophyB':'trophyA'):'failedAttempt'):i===2?'paper':null;gain=i===4?.86:.32;
  }
  if(a.state==='error'){effect=i===4?'snap':i===5?'failedAttempt':i===2?'ratchet':null;gain=i===5?.78:.48;}
  add(times[i]*a.seconds,stage,effect,gain,{beat:i});
 }
 if(typingActions.includes(a.action)&&!quietStates.includes(a.state)){
  // Motion itself has little bursts and rests. Quiet mix picks a subset of these contacts.
  for(const [i,u]of[.16,.205,.237,.31,.455,.482,.518,.67,.704,.742].entries()){
   const stage=Math.min(7,Math.max(1,Math.floor(u*9)));
   add(u*a.seconds,stage,a.mood==='wounded'?'softKey':['key','keyB','keyC','space'][i%4],.53,{press:i,beat:i});
   add((u+.013)*a.seconds,stage,null,0,{press:-1,beat:i});
  }
 }
 // Hold the home pose before the seam as well as at it. SVG's float time API
 // may land just below duration, so an endpoint-only reset is not sufficient.
 add(a.seconds*.98,0);
 steps.sort((a,b)=>a.at-b.at);
 // A typed contact can coincide with an authored body pose. Merge that instant
 // into one frame (the later contact wins), never duplicate SMIL keyTimes.
 for(let i=steps.length-1;i>0;i--)if(steps[i].at===steps[i-1].at)steps.splice(i-1,1);
 return {steps,policy:quietStates.includes(a.state)?'silent':sustainedStates.includes(a.state)?'loop':'entry',intervalSeconds:0};
}

function eye(x,y,w,h,c=P.ink){const hw=(w-4)/2,hh=(h-4)/2;return slab(x,y,hw,hh,c)+slab(x+hw+4,y,hw,hh,c)+slab(x,y+hh+4,hw,hh,c)+slab(x+hw+4,y+hh+4,hw,hh,c);}
function brow(x,y,ascending,c=P.ink){return [0,1,2].map(i=>rect(x+i*12,y+(ascending?2-i:i)*3,12,4,c)).join('');}
function face(a,s,blink=false){
 const m=a.mood,quiet=a.sharedQuiet,success=a.outcome==='success',ink=success?P.dark:P.ink,bg=success?P.gold:P.black;
 let eyes='',lips='',decor='',gaze=s===0?0:[0,-3,2,-2,3,0,-1,2,0][s];
 if(quiet||blink){eyes=slab(66,88,42,6,ink)+slab(212,88,42,6,ink);lips=rect(149,123,22,4,ink);}
 else if(m==='calm'){eyes=eye(65+gaze,64,48,42,ink)+eye(207+gaze,64,48,42,ink);lips=path('M149 124h5v4h12v-4h5v8h-22Z',ink);}
 else if(m==='engaged'){eyes=eye(64+gaze*2,58,48,48,ink)+eye(208+gaze*2,58,48,48,ink);lips=rect(147,125,26,5,ink);decor=rect(62,47,24,4,ink)+rect(234,47,24,4,ink);}
 else if(m==='annoyed'){
  eyes=eye(68+4,70,40,36,ink)+eye(212+4,65,40,41,ink)+rect(70,68,43,14,bg)+rect(212,63,44,8,bg);lips=rect(147,126,27,5,ink)+rect(169,131,6,3,ink);decor=rect(71,60,39,4,ink)+rect(213,54,36,4,ink);
 }else if(m==='irritated'){
  const twitch=[2,3,5].includes(s)?4:0;eyes=eye(68,67+twitch,40,40-twitch,ink)+eye(211,62,42,44,ink)+rect(68,67+twitch,40,8,bg);lips=rect(145,125,12,5,ink)+rect(157,128,13,5,ink)+rect(170,125,5,5,ink);decor=brow(68,54,false,ink)+rect(213,51,38,5,ink)+(twitch?rect(268,69,8,4,P.red)+rect(276,77,4,8,P.red):'');
 }else if(m==='whiny'){
  eyes=eye(62,57,52,50,ink)+eye(206,57,52,50,ink);decor=brow(67,46,true,ink)+brow(211,46,false,ink)+rect(69,91,38,9,P.blue)+rect(213,91,38,9,P.blue);lips=path('M145 126h8v-5h14v5h8v9h-8v5h-14v-5h-8Z',ink)+rect(152,128,16,5,P.cheek);
  if(s>0&&s<8)for(const x of[72,222])for(let j=0;j<3;j++){const y=107+((s*10+j*17)%55);decor+=rect(x+(j%2)*8,y,j===1?4:6,j===1?4:6,[P.blue,P.lightWater,P.water][j]);}if(s===5)decor+=burst(86,162,2,P.blue,4)+burst(232,162,2,P.blue,4);
 }else if(m==='wounded'){
  eyes=eye(66,60,46,46,ink)+eye(208,60,46,46,ink);decor=brow(68,44,true,ink)+brow(212,44,false,ink)+rect(74,93,28,7,P.blue)+rect(216,93,28,7,P.blue);lips=rect(148,126,8,4,ink)+rect(156,122,12,4,ink)+rect(168,126,4,4,ink);
  if(s===3||s===6)decor+=rect(77,106+(s===6?12:0),6,6,P.lightWater); // one held tear, not sad's waterfall
 }
 if(a.outcome==='failure'||a.state==='error')lips=rect(147,126,26,5,ink); // factual result overrides a smile, never the stored mood
 const cheeks=quiet?'':rect(49,115,14,8,P.cheek)+rect(68,115,14,8,P.cheek)+rect(238,115,14,8,P.cheek)+rect(257,115,14,8,P.cheek);
 let dx=0,dy=0;
 if(s){const curves={calm:[[0,0],[0,0],[0,-1],[0,-1],[0,0],[0,-2],[0,-1],[0,0],[0,0]],engaged:[[0,0],[-2,0],[2,-2],[-2,0],[2,-2],[0,-3],[2,0],[-1,0],[0,0]],annoyed:[[0,0],[3,0],[4,1],[4,1],[-2,0],[-3,0],[3,1],[3,0],[0,0]],irritated:[[0,0],[-3,1],[3,-2],[-3,2],[4,0],[-2,-3],[3,1],[-2,0],[0,0]],whiny:[[0,0],[-3,2],[2,4],[-3,2],[3,4],[0,-2],[-2,3],[2,1],[0,0]],wounded:[[0,0],[0,2],[-3,5],[-4,6],[0,3],[2,1],[0,4],[-1,2],[0,0]]};[dx,dy]=quiet?[0,s<5?2:0]:curves[m][s];}
 if(a.state==='poked'&&s>=2&&s<=4)dy+=s===2?8:3;
 if(a.state==='tap_spam'&&s>=2&&s<=6)dy+=s%2?12:6;
 // The face and its mouth are tagged, so a renderer can find the one that shows
 // in each flip-book step (facegen's face and mouth roles; the device's talking
 // mouth), and so is the step's blink (the popover's tile blinks with it).
 return at(dx,dy,group(eyes+group(lips,'data-part="mouth"')+cheeks+decor,`data-part="face" data-face="${quiet?'shared-rest':m}"${blink?' data-blink="1"':''}`));
}

function work(a,s,press){
 const k=a.action,m=a.mood,p=press??(s*3)%20,active=s>0&&s<8,phase=Math.max(0,s-1),dx=[0,0,14,28,42,58,72,32,0][s];let art=desk();
 if(['flow-keys','split-keys','tear-type','tissue-type','umbrella-work','cautious-key'].includes(k)){
  art+=k==='split-keys'?board(39,159,106,p%10)+board(176,159,106,(p+4)%10):board(83,158,154,p);
  const padX=m==='wounded'&&[2,3].includes(s)?58:100;
  art+=pad(padX,active?148+(p%2)*5:151)+pad(195,active?153-(p%2)*5:151);
  if(k==='tissue-type')art+=slab(34,161,38,26,P.prop)+rect(44,153-(s%4)*9,16,14+(s%4)*9,P.ink)+rect(53,143-(s%4)*9,13,16,P.ink);
  if(k==='umbrella-work')art+=path('M90 138h140v-8h-12v-8h-24v-8h-68v8h-24v8H90Z',P.blue)+rect(157,138,6,28,P.prop);
  if(k==='cautious-key'&&[2,3].includes(s))art+=rect(49,145,6,6,P.blue);
  if(k==='tear-type'&&active)art+=[70,226].map(x=>[0,1,2,3].map(j=>rect(x+(j%2)*8,119+((s*11+j*13)%57),5,5,[P.blue,P.water,P.lightWater][j%3])).join('')).join('')+(s%2?burst(90,178,1,P.blue,4):'');
  return art;
 }
 if(k==='tea-desk'){art+=board(109,163,138,p)+slab(42,153,42,31,P.prop)+rect(84,158,12,18,P.prop)+rect(87,162,5,9,P.black)+rect(38,185,52,4,P.dim);if(active)art+=[0,1,2].map(i=>rect(49+i*11,145-((s*5+i*7)%22),5,5,P.dim)).join('');return art+pad(181,155+(s%2)*4);}
 if(k==='file-garden'||k==='card-sort'){art+=[65,138,211].map((x,i)=>slab(x,167,46,21,P.dim)+rect(x+5,171,36,4,P.blue)+(s>i+1?paper(x+7,148,30,30,P.blue,i):'')).join('');return art+(active?at(dx-30,-Math.min(16,s*3),paper(107,151,35,32)+pad(131,164,20,16)):'');}
 if(k==='polish-row'){art+=board(89,157,150,-1);if(active)art+=rect(60+dx*2,155,42,14,P.blue)+pad(70+dx*2,141,30,20)+[0,1,2,3].map(i=>rect(65+dx*2+i*11,176+(i%2)*4,4,4,P.dim)).join('');return art+path('M254 173h34v15h-34v-5h28v-6h-28Z',P.prop);}
 if(k==='paper-fold'){return art+folder(216,143,60,37)+(s<3?paper(109,143,84,42):s<6?at(0,s%2*3,path('M116 145h68v12h-15v12h-38v-12h-15Z',P.prop)+rect(141,146,19,16,P.blue)):paper(140+dx,152,32,28))+pad(87,154)+pad(202,154);}
 if(k==='cube-belt'){art+=rect(49,177,224,10,P.dim)+[0,1,2,3].map(i=>cube(58+((i*48+dx*2)%192),153,22)).join('');return art+slab(239,139,45,48,P.prop)+rect(244,149,30,22,P.black);}
 if(k==='cable-knit'||k==='cable-tug'){art+=[75,145,215].map((x,i)=>slab(x,159,30,26,P.dim)+rect(x+6,165,16,10,P.black)+(s>i+2?rect(x+10,141,8,27,P.blue):'')).join('');const offset=k==='cable-tug'&&s<5?(s%2?15:-10):0;return art+at(offset,0,path('M56 134h37v13h49v-19h58v14h53v-6h-47v-14h-70v19H99v-13H56Z',P.blue))+pad(41+offset,127);}
 if(k==='blueprint'){const width=s===0||s===8?36:80+s*16;return art+rect(160-width/2,142,width,42,deep)+rect(160-width/2,139,8,47,P.blue)+rect(152+width/2,139,8,47,P.blue)+(active?rect(118,150,34,21,P.blue)+rect(159,159,36,12,green)+pad(95+dx,132):'');}
 if(k==='reluctant-key'||k==='repeat-enter'){art+=board(54,166,110,p)+slab(197,145+(s%2?3:0),69,40,P.prop)+text('ENTER',203,159,1,P.black);return art+pad(active?196:144,active?128+(s%2)*13:143,40,24)+(k==='repeat-enter'&&s>2&&s<7?burst(227,169,s%2,P.prop,4):'');}
 if(k==='crooked-stack'||k==='drag-stack'){const start=k==='drag-stack'?222-dx*1.6:127;for(let i=0;i<4;i++)art+=paper(Math.round(start+(k==='crooked-stack'&&s%3===0?i*5:0)),174-i*12,66,18,P.blue,i);return art+pad(Math.round(start-26),152)+(k==='drag-stack'?rect(55,169,Math.max(4,start-55),5,P.prop):'');}
 if(k==='stuck-drawer'){const pull=[0,2,4,0,5,28,32,12,0][s];return art+slab(87,135,148,52,P.dim)+rect(95,142,132,37,P.black)+at(-pull,0,slab(104,145,130,36,P.prop)+rect(157,153,30,8,P.black)+pad(155,160,34,20));}
 if(k==='pencil-flick'||k==='red-pencil'||k==='erase-again'){
  art+=paper(99,141,120,43,P.blue);const px=k==='pencil-flick'&&s>2&&s<6?135+(s-2)*34:110+(s%4)*19;
  if(k==='erase-again')art+=slab(px,148,33,19,P.prop)+[0,1,2,3,4].map(i=>rect(105+i*20,180-(i%2)*4,4,4,P.dim)).join('');
  else art+=at(px,135+(s%3)*4,rect(0,0,9,35,k==='red-pencil'?P.red:P.amber)+path('M0 35h9l-4 8Z',P.ink));
  if(k==='red-pencil'&&active)art+=path('M120 150h4v4h4v4h4v4h4v4h4v4h-4v-4h-4v-4h-4v-4h-4v-4h-4Z',P.red)+rect(160,158,38,5,P.red);
  return art+pad(px-8,135,27,18);
 }
 if(k==='jammed-feed'){art+=slab(56,145,75,42,P.dim)+rect(64,151,58,10,P.black);for(let i=0;i<(active?s:1);i++)art+=rect(117+i*16,157+(i%2)*8,22,13,P.prop);return art+pad(223,145+(s%2)*10);}
 if(k==='ratchet-kick'||k==='pout-crank'){art+=cog(166,162,24,P.prop,s)+rect(191,157,35,8,P.dim)+pad(211,142+(s%3)*9);if(k==='ratchet-kick'&&s>2&&s<7)art+=burst(168,169,s%3,P.dim,5);return art;}
 if(k==='patch-paper'){art+=paper(94,141,62,42)+paper(164,141,62,42);if(s>2&&s<8)art+=rect(147,151,28,24,P.amber)+rect(153,157,16,12,P.prop);return art+pad(86+(s>3?35:0),144)+pad(207-(s>3?30:0),146);}
 if(k==='shield-desk'){art+=board(100,163,123,p);return art+slab(65,active?145:166,42,40,P.blue)+pad(80,159)+pad(183,153+(s%2)*4);}
 if(k==='peek-folder'){return art+board(90,164,140,p)+folder(114,active&&s<5?98:143,94,42,P.prop)+pad(101,active&&s<5?117:161)+pad(203,active&&s<5?117:161);}
 if(k==='collect-pieces'){art+=slab(128,155,66,33,P.dim)+rect(136,155,50,10,P.black);for(let i=0;i<4;i++){const x=active?Math.round([57,92,215,251][i]+(160-[57,92,215,251][i])*Math.min(.9,s/8)):[57,92,215,251][i];art+=cube(x,169-(i%2)*8,14);}return art+pad(91,154)+pad(204,154);}
 throw new Error('Unauthored working action '+k);
}

function props(a,step){
 const s=step.stage,k=a.action,active=s>0&&s<8,n=Math.min(3,Math.max(0,s-1)),dx=[0,0,18,36,54,72,90,40,0][s],c=a.outcome==='success'?P.dark:P.blue;
 if(a.state==='working')return work(a,s,step.press);
 if(a.state==='asleep'){
  if(k==='dream')return active?rect(265,67-s*4,8,8,P.dim)+(s>4?rect(282,40,4,4,P.dim):''):'';
  if(k==='resettle')return slab(85+(s>3&&s<7?6:0),150,152,24,P.dim)+rect(100,154,120,5,P.prop);
  return '';
 }
 if(a.state==='no_app')return(k==='blanket'?slab(51,143+(active?s%3:0),218,37,P.dim)+rect(61,149,198,5,P.prop):'')+at(k==='plug-rest'&&active?s%3*4:0,0,plug(137,160,P.dim));
 if(a.state==='idle'){
  if(k==='stretch'&&active)return pad(30-dx/6,115-s%3*4,30,24)+pad(260+dx/6,115-s%3*4,30,24);
  return '';
 }
 if(a.state==='listening'){
  if(k==='focus')return [0,1].map(i=>at(i?250:39,49,rect(0,0,30,5,P.blue)+rect(i?25:0,0,5,27,P.blue)+rect(0,98,30,5,P.blue)+rect(i?25:0,76,5,27,P.blue))).join('');
  if(k==='headset')return at(0,active?0:-12,rect(56,26,208,8,P.dim)+rect(48,34,8,84,P.dim)+rect(264,34,8,84,P.dim)+slab(35,82,25,46,P.blue)+slab(260,82,25,46,P.blue));
  return at(active?-s%3*3:0,0,path('M251 127h12v-12h12v-12h19v63h-19v-12h-12v-12h-12Z',P.amber)+rect(235,131,20,10,P.prop));
 }
 if(a.state==='starting'){
  const label={new_task:'NEW TASK',session:'READY',continuation:'CONTINUE',compacted:'COMPACTED'}[a.startContext];
  if(k==='placard')return(s>1&&s<7?held(label,147,P.blue):board())+(s===1?pad(80,165)+pad(213,165):'');
  if(k==='ticket')return slab(63,146,62,42,P.dim)+rect(69,150,50,9,P.black)+(active?card(label,148,P.prop)+pad(220,159):'');
  return rect(59,137,202,49,P.dim)+rect(67,142,186,39,P.black)+(active?centered(label,156,2,P.blue):'')+[0,1,2].map(i=>rect(64,139+i*11,192,7,s>i+1&&s<7?P.black:P.prop)).join('');
 }
 if(a.state==='planning'){
  if(k==='route')return [76,138,200].map((x,i)=>paper(x,147+(i===1?16:0),44,27)+text(String(i+1),x+17,154+(i===1?16:0),1,P.blue)+(s>i+2?arrow(x+44,158,P.blue):'')).join('');
  if(k==='blueprint'){const w=active?150:40;return rect(160-w/2,138,w,47,deep)+rect(155-w/2,133,10,57,P.blue)+rect(155+w/2,133,10,57,P.blue)+(active?rect(99,145,30,21,green)+rect(143,154,30,24,P.blue)+rect(188,145,30,21,green)+pad(91+dx,132):'');}
  return [68,132,196].map((x,i)=>rect(x,142,54,44,P.dim)+rect(x+5,147,44,34,P.black)+paper(x+10,151,34,24,i===1?P.amber:P.blue)).join('')+(active?at(s>3?64:0,0,paper(142,133,34,25,P.amber)):'');
 }
 if(a.state==='terminal'){
  if(k==='matrix')return board(83,159,154,step.press??s*3)+[23,277].map((x,j)=>[0,1,2,3,4].map(i=>text((i+j+s)%2?'01':'10',x,32+((i*25+s*7)%112),1,green)).join('')).join('')+pad(104,149+s%2*4)+pad(190,152-s%2*4);
  if(k==='console')return rect(50,137,220,52,deep)+rect(56,143,208,40,P.black)+text('> RUN()',65,148,2,green)+rect(65+((s*17)%175),172,10,7,green)+pad(37,162)+pad(259,162);
  return slab(46,141,67,46,P.dim)+rect(55,149,49,8,P.black)+rect(113,149,155,35,deep)+text(s%2?'0101 1010':'RUN() X++',119,154,2,green)+cog(75,177,12,P.prop,s)+pad(42,165);
 }
 if(a.state==='tool_use'){
  if(k==='toolbox')return slab(69,153,170,36,P.dim)+rect(78,159,151,24,P.black)+rect(130,143,48,10,P.prop)+(active?at(104+dx/2,123,path('M0 0h10v14h10V0h10v22H20v37H10V22H0Z',P.prop))+pad(117+dx/2,147):rect(122,166,76,8,P.prop));
  if(k==='socket')return plug(78+(active?Math.min(dx,66):0),156)+slab(221,147,40,42,P.dim)+rect(225,155,27,26,P.black)+pad(69+(active?Math.min(dx,66):0),145);
  return cog(118,159,24,P.prop,s)+cog(164,159,20,P.blue,s+1)+rect(186,155,45,8,P.dim)+pad(215,142+s%3*8);
 }
 if(a.state==='searching'){
  if(k==='globe')return slab(124,132,66,55,P.blue)+rect(152,133,8,54,P.black)+rect(130,155,54,7,P.black)+rect(137,135,4,50,P.black)+rect(173,135,4,50,P.black)+lens(65+dx,132)+(s>4&&s<8?paper(239,146,39,33):'');
  if(k==='radar')return slab(106,128,107,60,deep)+rect(154,134,6,48,green)+rect(114,158,91,5,green)+at(159,160,rect(-37+Math.min(6,s)*12,-23,5,45,green))+[0,1,2].map(i=>rect(120+i*30,144+(i%2)*25,7,7,s>i+2?P.amber:P.dim)).join('');
  return rect(122,174,65,8,P.dim)+rect(150,151,7,29,P.prop)+at(active?dx/3:0,0,rect(81,138,106,19,P.prop)+slab(179,131,31,32,P.blue)+rect(78,137,12,24,P.dim))+pad(108,156);
 }
 if(a.state==='analyzing'){
  if(k==='compare')return paper(70,143,62,43,P.blue)+paper(190,143,62,43,P.amber,1)+(active?lens(s%2?72:190,135):'');
  if(k==='lens')return paper(97,137,111,50)+lens(96+dx/2,130)+(s>3&&s<7?rect(115+dx/2,148,12,12,P.blue):'');
  return [62,138,214].map((x,i)=>slab(x,165,46,23,P.dim)+paper(x+5,147,35,32,i===1?P.amber:P.blue,i)).join('')+(active?at(dx,0,paper(65,130,30,26,P.amber)+pad(84,143,22,16)):'');
 }
 if(a.state==='testing'){
  if(k==='gate')return rect(109,133,10,54,P.amber)+rect(201,133,10,54,P.amber)+rect(109,129,102,9,P.amber)+cube(56+dx*1.8,159,24,P.blue)+rect(124,144+(s%4)*8,73,4,P.amber);
  if(k==='bench')return slab(68,154,184,34,P.dim)+[94,150,206].map(x=>rect(x,161,19,19,P.black)).join('')+rect(91,138,16,17,P.prop)+pad(81,active?132+s%2*7:126,36,19)+text('TEST',145,142,1,P.amber);
  return [0,1,2].map(i=>cube(80+i*64,151+(i===s%3?-9:0),28,P.blue)).join('')+lens(70+(s%3)*64,127,P.amber);
 }
 if(a.state==='delegating'){
  if(k==='hatch')return rect(58,184,204,7,P.dim)+[0,1,2].slice(0,n).map(i=>robot(77+i*68+(s>5?(s-5)*13:0),148,s,P.blue,true)).join('')+(s===1?rect(71,159,178,25,P.dim):'');
  if(k==='squad')return [0,1,2].map(i=>robot(69+i*74+(s>5?(s-5)*19:0),148,s===3?3:s,P.blue,true)).join('')+(s>2&&s<6?card('GO!',112,P.amber)+pad(46,50,26,23):'');
  return [0,1,2].map(i=>rect(65+i*72,132,7,35,P.dim)+rect(65+i*72,167,40,6,P.dim)+robot(70+i*72,150,s,P.blue,false)+(active?cube(70+i*72,131+(s%3)*7,14,P.amber):'')).join('');
 }
 if(a.state==='helper_return'){
  if(k==='courier')return robot(active?35+dx:26,148,s,P.blue,true)+(s>3&&s<8?held('REPORT',149):'');
  if(k==='salute')return [0,1,2].map(i=>robot(57+i*88,148,s===3||s===4?3:0,P.blue)).join('')+(s>3&&s<8?card('REPORT',109):'');
  return slab(212,129,55,51,P.blue)+rect(215,136,49,32,P.black)+rect(265,127,6,50,P.dim)+rect(271,127,18,12,active?P.amber:P.dim)+(active?held('REPORT',148):'');
 }
 if(a.state==='waiting'){
  if(k==='hourglass')return rect(242,127,40,7,P.prop)+rect(242,180,40,7,P.prop)+path('M247 134h30v9h-8v8h-8v8h8v8h8v13h-30v-13h8v-8h8v-8h-8v-8h-8Z',P.dim)+rect(258,139+(s%4)*10,7,7,P.amber);
  if(k==='chair')return slab(80,172,160,13,P.dim)+rect(90,180,8,12,P.dim)+rect(222,180,8,12,P.dim)+pad(92,160+s%2*3)+pad(201,160+s%2*3);
  return rect(266,124,5,25,P.dim)+rect(250+(s%5)*6,149,20,20,P.prop)+rect(244,123,51,5,P.dim);
 }
 if(a.state==='needs_you')return requestArt(a,step);
 if(a.state==='reply_ready'){
  if(k==='tray')return rect(67,180,186,7,P.dim)+(active?held('ANSWER',146):paper(127,151,67,32));
  if(k==='scroll'){const w=active?184:38;return rect(160-w/2,146,w,37,P.prop)+rect(152-w/2,141,9,48,P.blue)+rect(159+w/2,141,9,48,P.blue)+(active?centered('ANSWER',155,2,P.black):'');}
  return slab(87,148,145,39,P.blue)+path('M92 149h65v14h10v-14h60v5h-55v14h-20v-14H92Z',P.black)+(active?card('ANSWER',133,P.prop):'');
 }
 if(a.state==='task_complete'){
  if(a.outcome==='success'){
   const fireworks=active?[burst(42,52,s%4,P.ochre),burst(272,57,(s+2)%4,P.ochre),burst(60,145,s%3,P.cheek,5)].join(''):'';
   if(k==='cup')return fireworks+(active?cup(139,106,.75)+held('COMPLETE',155,P.dark).replaceAll(`fill="${P.black}"`,`fill="${P.gold}"`):'');
   if(k==='ribbon')return fireworks+(active?at(135,104,star(0,0,52,P.ochre)+rect(7,37,10,18,P.dark)+rect(33,37,10,18,P.dark))+card('COMPLETE',158,P.prop):'');
   return fireworks+rect(68,178,184,10,P.ochre)+rect(116,165,88,16,P.dark)+(active?cup(143,100,.6)+card('COMPLETE',143,P.prop):'');
  }
  if(k==='fallen-tower')return(s<4?[0,1,2].map(i=>cube(149,163-i*22,22,P.prop)).join(''):[cube(99,155,22,P.prop),cube(205,164,22,P.prop),cube(159,173,16,P.dim)].join(''))+(s>=4&&s<8?held('FAILED',129,P.amber):'');
  if(k==='torn-result')return paper(112-(s>3?30:0),145,47,39,P.prop)+paper(161+(s>3?30:0),145,47,39,P.prop)+(s>=4&&s<8?card('FAILED',113,P.amber):'');
  return rect(93,170,134,16,P.dim)+rect(131,150+(s>3?12:0),58,20,P.prop)+(s>=4&&s<8?held('FAILED',121,P.amber):'');
 }
 if(a.state==='error'){
  let art=k==='jam'?cog(150,162,25,P.dim,s)+rect(179,158,48,8,P.prop)+(s===4?burst(160,164,2,P.prop):''):k==='cable'?plug(94-(s>3?32:0),157)+slab(211,148,36,39,P.dim)+rect(216,158,22,19,P.black):slab(85,146,66,41,P.dim)+paper(137,150,87,34,P.amber);
  return art+(s>=4&&s<8?card('ERROR',113,P.amber):'');
 }
 if(a.state==='stopped'){
  if(k==='brake')return rect(57,179,208,10,P.dim)+cube(86+(s<4?s*18:54),155,23)+pad(201,s<4?144:163)+(s>3&&s<8?card('STOPPED',121,P.prop):'');
  if(k==='lid')return board(83,158,154,-1)+(active?rect(83,139+s*4,154,Math.max(4,48-s*4),P.dim):'');
  return rect(191,128,7,59,P.prop)+card('STOPPED',131,P.prop)+slab(69+Math.min(3,s)*10,169,81,16,P.dim);
 }
 if(a.state==='poked'){
  if(k==='squash')return active?slab(142,137,36,24,P.prop)+(s<5?burst(158,143,Math.min(s,3),P.dim,4):''):'';
  if(k==='peek')return active?slab(s%2?22:260,78,37,29,P.prop):'';
  return active?pad(220-dx/3,115-(s%3)*6,44,36)+(s===4?burst(225,132,1,P.blue,4):''):'';
 }
 if(a.state==='tap_spam'){
  const impacts=active?slab(s%2?24:254,56+(s%3)*27,40,32,P.prop)+burst(s%2?46:273,83+(s%3)*27,1,P.dim,4):'';
  if(k==='shield')return impacts+(active?slab(72,123,176,65,P.blue)+card('EASY!',139,P.prop):'');
  if(k==='duck')return impacts+(s>3&&s<8?card('EASY!',155,P.prop):'');
  return impacts+(active?rect(21,41,105+(s%2)*22,126,P.blue)+rect(193-(s%2)*22,41,106,126,P.blue)+rect(21,35,278,7,P.dim)+card('EASY!',150,P.prop):'');
 }
 throw new Error('Unauthored state '+a.state);
}

function requestArt(a,step){
 const s=step.stage,p=moodProfiles[a.mood],i=step.hit||0;
 let art=rect(122,15,76,6,P.amber)+[0,1,2].map(j=>rect(140+j*16,26,8,8,P.amber)).join(''); // persistent pending indicator
 if(s>=1&&s<=4){
  const locations={calm:[[66,74],[229,83]],engaged:[[66,67],[231,87],[145,54]],annoyed:[[229,82],[76,84],[227,82]],irritated:[[57,74],[238,60],[74,116],[220,99]],whiny:[[88,117],[207,121],[139,132]],wounded:[[83,121],[209,121]]};
  const [x,y]=locations[a.mood][i%locations[a.mood].length],offset=s===1?12:s===2?0:s===3?4:8;
  if(a.action==='card-knock')art+=at(x-26,y-13+offset,slab(0,0,68,42,P.prop)+text('ASK',15,12,2,P.black)+pad(-9,21,22,20));
  else art+=pad(x-19,y-10+offset,a.mood==='irritated'?46:38,a.mood==='wounded'?26:30);
  if(s===2||s===3)art+=burst(x,y+7,s===2?1:2,a.mood==='irritated'?P.amber:P.blue,6);
 }
 if(s>=5&&s<=8){
  const shift=s===8?-132:0;
  if(a.action==='bell-pull')art+=at(0,shift,rect(247,37,6,73,P.prop)+pad(232,87,35,28)+path('M138 41h44v15h24v17h14v54h16v18H84v-18h16V73h14V56h24Z',P.amber)+rect(149,145,22,12,P.prop)+(s===5?burst(159,109,3,P.amber):''));
  else art+=at(0,shift,slab(45,43,230,137,amberDark)+rect(45,43,230,8,P.amber)+bang(70,71,P.amber)+text(a.action==='card-knock'?'YOU':'ASK',121,75,4,P.amber)+rect(122,120,102,6,P.prop)+rect(122,136,69,6,P.prop));
 }
 return art;
}

function background(a,s){
 if(a.outcome!=='success')return '';
 // Slow tone shifts and traveling coarse tiles, not a full-screen strobe.
 const colors=[P.gold,'#FFD14A','#FFC54A','#FFBA4A','#FFC54A','#FFD14A',P.gold,'#FFD84A',P.gold];
 return rect(0,0,320,192,colors[s])+[0,1,2,3,4].map(i=>rect(((i*76+s*12)%380)-30,13+(i%3)*48,36,9,'#EDAE26')).join('');
}
function frames(a,plan,draw,part){
 const drawings=plan.steps.slice(0,-1).map((step,i)=>({art:draw(step),i})),unique=[...new Set(drawings.map(x=>x.art))];
 return group(unique.map(art=>{
  const indexes=drawings.filter(d=>d.art===art).map(d=>d.i);
  const values=plan.steps.map((_,i)=>Number(indexes.includes(i)||i===plan.steps.length-1&&indexes.includes(0)));
  return group(`<animate attributeName="opacity" values="${values.join(';')}" keyTimes="${plan.steps.map(x=>round(x.at/a.seconds)).join(';')}" dur="${a.seconds}s" repeatCount="indefinite" calcMode="discrete"/>`+art,`opacity="${indexes.includes(0)?1:0}" data-step="${indexes.join(',')}"`);
 }).join(''),`data-part="${part}"`);
}
function renderMoodScene(a){
 const plan=moodPlan(a),id='boop-v4-'+a.id.replaceAll('.','-');
 const art=frames(a,plan,e=>background(a,e.stage),'mood-background')+frames(a,plan,e=>face(a,e.stage,e.stage===8),'mood-face')+frames(a,plan,e=>props(a,e),'mood-action');
 const stillStep={stage:a.state==='needs_you'?6:a.state==='task_complete'||a.state==='error'?5:0};
 const still=background(a,stillStep.stage)+face(a,0)+props(a,stillStep);
 return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="${id}" data-mood="${a.mood}" data-state="${a.state}" data-action="${a.action}" data-loop-seconds="${a.seconds}" data-text-top="192" role="img" aria-labelledby="${id}-title ${id}-desc" shape-rendering="crispEdges" overflow="hidden"><title id="${id}-title">${safe(a.mood+' · '+a.name)}</title><desc id="${id}-desc">${safe(a.caption+' '+moodProfiles[a.mood].character)} Loopable pixel animation; procedural synchronized SFX; bottom 48 pixels reserved for host text.</desc><defs><clipPath id="${id}-clip"><rect width="320" height="192"/></clipPath></defs><style>#${id} .still{display:none}@media(prefers-reduced-motion:reduce){#${id}:not([data-motion="on"]) .motion{display:none}#${id}:not([data-motion="on"]) .still{display:inline}}</style><rect width="320" height="240" fill="#000000"/><g clip-path="url(#${id}-clip)"><g class="motion">${art}</g><g class="still">${still}</g></g><g data-part="reserved-text-zone"/></svg>`;
}
function moodScore(a){
 const plan=moodPlan(a),profile=moodProfiles[a.mood];
 const events=plan.steps.flatMap((s,i)=>s.effect?[{at:s.at,effect:s.effect,gain:round(s.gain*(['needs_you','task_complete','error'].includes(a.state)?1:profile.gain)),pitch:['alertDing','trophyA','trophyB','failedAttempt'].includes(s.effect)?1:profile.pitch,label:s.effect==='alertDing'?'Ding · request revealed':`${a.action} · contact ${i}`,sync:{part:'mood-action',step:i,pose:'stage-'+s.stage}}]:[]);
 for(const e of events)if(!effects[e.effect])throw new Error('Missing effect '+e.effect);
 return {id:a.id,seconds:a.seconds,policy:plan.policy,intervalSeconds:plan.intervalSeconds,character:profile.character,description:a.caption+' Sparse code-generated material effects, no speech or music bed.',events,tailSeconds:round(Math.max(0,...events.map(e=>e.at+effects[e.effect].duration-a.seconds)))};
}
// When speech may enter over a scene, in seconds: .12 s after its last
// attention cue ends for needs_you, task_complete and error, else .45 s.
// The quiet mix keeps those states' cues, so the score may be mixed or not.
function voiceStart(state,score){
 return protectedSoundStates.includes(state)?Math.max(0,...score.events.map(e=>e.at+effects[e.effect].duration))+.12:.45;
}
function voiceWindows(a){
 const start=voiceStart(a.state,moodScore(a)),protectedScene=protectedSoundStates.includes(a.state);
 return {suggested: true,duckRoutineSfx:!protectedScene,earliestEntry:round(start),latestExit:round(a.seconds-.25),fitsWithinCycle:start<a.seconds-.25,note:'Candidate entry/exit bounds, not a generated recording. If the take does not fit, extend the host hold or follow after the animation; never speed up speech to force it.'};
}

return {moodPlan,renderMoodScene,moodScore,voiceStart,voiceWindows};},
"mood-catalog.mjs":()=>{
// Six new characters. No mood aliases and no externally selected intensity.
const newMoods=['calm','engaged','annoyed','irritated','whiny','wounded'];
const moodProfiles={
 calm:{pace:1.22,gain:.48,pitch:.98,knocks:[.55,1.24],tapGain:.27,character:'Settled, big-eyed and unhurried; small precise motions, soft content breaths.'},
 engaged:{pace:.94,gain:.62,pitch:1.02,knocks:[.42,.73,1.11],tapGain:.46,character:'Alert eyes track the next step; compact confident flow, no straining or anger.'},
 annoyed:{pace:1.10,gain:.56,pitch:.96,knocks:[.50,1.14,1.40],tapGain:.44,character:'Held side-eye, compressed mouth, reluctant corrections and a long dry pause.'},
 irritated:{pace:.83,gain:.65,pitch:.98,knocks:[.32,.49,.81,.98],tapGain:.65,character:'Twitching eye, uneven clipped motions and quick corrective jabs; not full grumpy destruction.'},
 whiny:{pace:1.16,gain:.48,pitch:1.05,knocks:[.62,1.19,1.48],tapGain:.28,character:'Baby pout, watery eyes and cube tears while still doing the work; an active plea for sympathy.'},
 wounded:{pace:1.30,gain:.40,pitch:.98,knocks:[.76,1.60],tapGain:.20,character:'Glassy eyes, inward flinch, hesitant approach then retreat; quietly checking if you still care.'}
};
// Different props and actions, not renamed timings of one performance.
const workActions={
 calm:[['flow-keys','Unhurried flow','A short typing phrase, a breath, then a careful final key.'],['tea-desk','Tea beside the task','Set down a steaming block cup; type a small phrase beside it.'],['file-garden','Tidy little garden','Plant three work tiles into orderly slots, then close the tray.'],['polish-row','A clean workspace','Sweep square dust into a pan; straighten the workstation.'],['paper-fold','Fold and file','Fold a sheet into a little packet and tuck it into a folder.']],
 engaged:[['split-keys','Two-track flow','Alternate between two compact keyboards and bring the results together.'],['card-sort','Sort the incoming work','Catch sliding cards and distribute them into three trays.'],['cube-belt','Keep the belt moving','Feed blocks along a belt into a slot, without claiming the task is complete.'],['cable-knit','Connect the pieces','Seat three chunky plugs into their matching sockets.'],['blueprint','Build from the plan','Unroll a blueprint, align its blocks and roll it up again.']],
 annoyed:[['reluctant-key','Fine, one more key','Pause in a side-eye, reach reluctantly, then press one oversized key.'],['crooked-stack','Stay. Straight.','Straighten a leaning stack; it tilts again, earning a dry side-eye.'],['stuck-drawer','Not this drawer again','Pull a sticking file drawer twice before easing it open.'],['pencil-flick','The pencil protest','Set a pencil down, flick it away, then retrieve it to keep working.'],['erase-again','Rub it out, again','Erase one line in broad strokes; push the square crumbs aside.']],
 irritated:[['repeat-enter','Enter, enter, ENTER','Three accelerating oversized Enter-key jabs and a clipped recoil.'],['cable-tug','The cable is tangled','Tug a chunky cable, recoil, untangle it and plug it in.'],['jammed-feed','Paper, please move','A paper feed jams; two corrections free the accordion sheet.'],['ratchet-kick','Stubborn little gear','Crank a resistant gear in short bursts; square dust shakes loose.'],['red-pencil','No, this bit','Rapidly mark, cross out and correct a page with a chunky red pencil.']],
 whiny:[['tear-type','Typing through a complaint','Continue typing while two lanes of blue cube tears splash beside the keys.'],['tissue-type','One paw for the tears','Pull a long tissue with one pad; keep typing with the other.'],['drag-stack','But it is so heavy','Drag a tall stack across the desk, pause to pout, then pull again.'],['pout-crank','Whimper and wind','Work a large crank through a drooping pout; tiny tear cubes bounce off it.'],['umbrella-work','A very small shelter','Open a tiny umbrella over the keyboard, then type beneath falling tear cubes.']],
 wounded:[['cautious-key','Careful little keystrokes','Approach the keyboard, flinch back, then try a softer short phrase.'],['patch-paper','Mend the little tear','Line up a torn page and smooth a square patch over it.'],['shield-desk','A sheltered desk','Raise a protective desk panel and keep working behind it.'],['peek-folder','Peek and continue','Hide briefly behind a folder, peek over it and carefully resume.'],['collect-pieces','Still picking up the pieces','Gather scattered work tiles into a small box and hold it close.']]
};
// Shared semantic actions, each performed with its own new-mood face and kinetics.
const definitions={
 no_app:[['doze','Disconnected doze','Closed eyes breathe beside an unconnected plug.'],['plug-rest','Plug at rest','Nudge the loose plug, then settle; no fake reconnection.'],['blanket','Waiting under a blanket','A small folded cover rises and settles over the resting face.']],
 asleep:[['breathe','Sleepy breathing','Quiet shared closed eyes, barely rising and settling.'],['dream','One dream square','A single dream block drifts up and disappears.'],['resettle','Pillow resettle','A broad pillow shifts; Boop settles back into the same pose.']],
 idle:[['blink','A moment to breathe','A readable mood face and one small blink.'],['look','Look left, look right','Glance around and return to center without inventing work.'],['stretch','Little stretch','Two soft pads stretch outward, then tuck away.']],
 listening:[['focus','I am listening','Broad corner brackets quietly settle around the face.'],['headset','Headset on','A blocky headset drops onto the head and gently lifts away.'],['trumpet','All ears','Lean toward a large simple listening trumpet.']],
 starting:[['placard','The opening card','Raise a factual start card and unfold the desk.'],['ticket','Task ticket','Pull a start ticket from a small printer, read it, then file it.'],['shutter','Open for work','Roll a little desk shutter up to reveal the start label.']],
 planning:[['route','A route in blocks','Arrange three numbered step cards into a zigzag route.'],['blueprint','Roll out the plan','Unroll a large plan, point to three areas, then roll it closed.'],['board','Rearrange the board','Move a middle note between three planning columns.']],
 terminal:[['matrix','Binary rain','Type below falling green block-code and binary columns.'],['console','Open the console','Unfold a terminal window; a chunky cursor advances along toy code.'],['code-reel','The code reel','Crank a narrow ribbon of toy code through a reader.']],
 tool_use:[['toolbox','Pick the right tool','Open a toolbox, choose a broad wrench, seat it, put it back.'],['socket','Make the connection','Bring a large plug across the screen and connect its socket.'],['gear','Turn the mechanism','Mesh two gears and work the large lever.']],
 searching:[['globe','Look around the world','Sweep a magnifier across a globe and send a query tile.'],['radar','Sweep for sources','A stepped radar sweep catches three source squares.'],['telescope','A long look','Extend a toy telescope, scan, then collect a source card.']],
 analyzing:[['compare','Compare the evidence','Hold two different pages, alternate scrutiny, then group them.'],['lens','Under the big lens','Move a magnifier over an enlarged page and reveal its block pattern.'],['sort','Clues into piles','Sort patterned source tiles into three evidence trays.']],
 testing:[['gate','Inspection gate','Feed sample cubes under an amber scanner; no invented result.'],['bench','Test bench','Press a test lever and inspect three unfilled result slots.'],['tiles','Test-case carousel','Rotate three sample tiles through a magnifier; no pass checkmark.']],
 delegating:[['hatch','Helpers from the hatch','Three little robots emerge with work parcels and move out.'],['squad','Squad, move out','A rounded-pad salute, a GO card and a small robot formation.'],['chutes','Work parcel launch','Send three work cubes down separate chutes to waiting helper robots.']],
 helper_return:[['courier','A report arrives','A tiny robot carries a report across the desk and hands it over.'],['salute','Reporting back','Helpers line up, salute with simple pads and present REPORT.'],['mailbox','Helper post','A mailbox flag rises; Boop takes a report envelope from the hatch.']],
 waiting:[['hourglass','Waiting, still here','A broad hourglass drops square grains, then turns.'],['chair','A patient seat','Lean on a small stool and gently shift position.'],['pendulum','Watching time','Track a quiet chunky pendulum; no numeric progress promise.']],
 needs_you:[['tap-panel','Knock and ask','Broad mood-shaped taps; the signature ding reveals a large ASK panel.'],['card-knock','The request card','Use a large request card to tap the screen, then reveal the alert.'],['bell-pull','Ring for you','Tap different areas, then pull a cord to reveal a broad block bell.']],
 reply_ready:[['tray','An answer on a tray','Open an answer sheet and slide the tray toward the user.'],['scroll','Unroll the answer','Unroll a wide answer scroll and hold it open.'],['envelope','An answer envelope','Present a large open envelope with an ANSWER card inside.']],
 task_complete:[['cup','Trophy lift','Raise a cup and COMPLETE card amid square fireworks.'],['ribbon','The completion rosette','Unfurl a broad rosette and COMPLETE ribbon.'],['podium','Onto the podium','Rise on a stepped podium, hold COMPLETE and celebrate.']],
 error:[['jam','A tool jam','A mechanism sticks and sheds a few square fragments; ERROR, not task over.'],['cable','Disconnected tool','A tool cable pops out; catch it and show ERROR.'],['page','The error slip','An ERROR slip emerges from a reluctant printer.']],
 stopped:[['brake','Tools down','Brake a moving belt; loose blocks settle under STOPPED.'],['lid','Close the workstation','Fold the keyboard into a case and lower the lid.'],['flag','Pause the production line','Plant a STOPPED flag; the work cart gently rolls to a halt.']],
 poked:[['squash','Squash and rebound','A broad soft contact squashes the face; it returns a mood-shaped look.'],['peek','Peek at the tap','Lean toward a side contact, inspect it, then draw back.'],['high-pad','A soft hello','Offer one large simple pad, make contact and tuck it away.']],
 tap_spam:[['shield','Easy, easy','Duck behind a large cushioned EASY shield as contacts arrive from both sides.'],['duck','Over here? Over there?','Dodge three broad contact patches, then look out from a low crouch.'],['curtain','A little privacy','Pull a small curtain across, peek out, then open it again.']]
};
const failure=[['fallen-tower','The work did not hold','A work tower splits into pieces; hold FAILED, no celebration.'],['torn-result','A broken result','A result sheet tears into two halves; present FAILED.'],['empty-podium','No trophy this time','An empty result stand lowers; a large FAILED card replaces it.']];
const durations={working:[5.4,6.2,5.8,6.7,5.6],starting:[5.4,6.2,5.8],needs_you:[5.6,6.2,6.7],task_complete:[6.4,6.8,7.2],terminal:[5.4,6.2,6.6],asleep:[9,10,12],no_app:[9,10,12],idle:[8,10,9],waiting:[7,8,9]};
const moodAdditions=newMoods.flatMap(mood=>Object.entries(definitions).flatMap(([state,defs])=>{
 const entries=state==='starting'?['new_task','session','continuation','compacted'].flatMap(startContext=>defs.map(d=>({d,startContext}))):state==='task_complete'?[...defs.map(d=>({d,outcome:'success'})),...failure.map(d=>({d,outcome:'failure'}))]:defs.map(d=>({d}));
 return entries.map(({d,startContext,outcome},i)=>make(mood,state,d,i+1,{...(startContext?{startContext}:{}),...(outcome?{outcome}:{})}));
}).concat(workActions[mood].map((d,i)=>make(mood,'working',d,i+1))));
function make(mood,state,[action,name,caption],variation,extra={}){
 const quiet=['asleep','no_app'].includes(state),pace=quiet||state==='task_complete'?1:moodProfiles[mood].pace;
 const seconds=Number(((durations[state]||[5.3,6.1,5.7])[(variation-1)%3]*pace+(state==='working'&&variation>3?.4:0)).toFixed(3));
 return {id:`${mood}.${state}.${String(variation).padStart(2,'0')}`,mood,state,variation,action,name,caption,seconds,renderer:'mood-v4',approval:'Review candidate',sharedQuiet:quiet,...extra};
}

return {newMoods,moodProfiles,workActions,moodAdditions};},
"needs-you.mjs":()=>{
const {palette,rect,path,group,at,face,move,star,label}=load("visual/base.mjs");
const {closeTimelines}=load("visual/loop.mjs");
const {requestPerformance,drawRequestPerformance}=load("request-performances.mjs");
// Fixed-size pixel art. The signal stays amber/dark; it never strobes a white
// screen or borrows the gold full-background treatment reserved for success.
const alertProfiles={
  happy:{pitch:1.06,gain:.92,tapGain:.42,recoil:2,impact:1,look:'friendly, bouncy gestures'},
  excited:{pitch:1.12,gain:.95,tapGain:.48,recoil:4,impact:1.05,look:'quick, eager gestures at changing positions'},
  proud:{pitch:.98,gain:.92,tapGain:.50,recoil:2,impact:.85,look:'deliberate, theatrical gestures'},
  curious:{pitch:1.04,gain:.88,tapGain:.36,recoil:2,impact:.8,look:'inquisitive gestures exploring different spots'},
  determined:{pitch:1,gain:.94,tapGain:.63,recoil:3,impact:1.1,look:'steady, firm gestures'},
  grumpy:{pitch:.91,gain:.98,tapGain:.80,recoil:5,impact:1.25,look:'rapid, heavy gestures'},
  sad:{pitch:.97,gain:.88,tapGain:.22,recoil:1,impact:.7,look:'hesitant, soft and slow gestures'}
};
const amber=palette.amber,dark='#352915',panel='#584020';
// All request graphics stay above the host's bottom 48 px text lane.
const requestLayout={width:320,height:240,textTop:192,textHeight:48,alertScale:.8,alertX:32};
const scaleAlert=art=>group(art,'transform="translate(32 0) scale(0.8)" data-part="scaled-alert"');
const attrs=s=>String(s).replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;');
const bang=(x,y,w=30,h=66,c=amber)=>rect(x,y,w,h,c)+rect(x,y+h+12,w,Math.round(w*.75),c);
function pending(){
  return group(rect(20,12,280,32,dark)+rect(20,40,280,4,amber)+bang(32,17,7,11)+
    [0,1,2].map(i=>rect(137+i*17,24,8,8,amber)).join('')+rect(271,21,12,12,amber),'data-part="pending-request"');
}
function moodCorners(mood,phase=0){
  if(mood==='grumpy')return [22,272].map(x=>at(x,18,path('M0 8h8V0h5v13H0ZM20 0h5v8h8v5H20ZM0 20h13v13H8v-8H0ZM20 20h13v5h-8v8h-5Z',palette.red))).join('');
  if(mood==='sad')return [25,282].map((x,j)=>[0,1,2,3].map(i=>rect(x+(i%2)*5,94+i*20+((phase+j)%2)*6,7,9,[palette.blue,palette.water,palette.lightWater][i%3])).join('')).join('');
  if(mood==='excited')return [20,288].map(x=>[40,61,82].map((y,i)=>rect(x,y+(phase%2)*4,12,5,i%2?palette.cheek:amber)).join('')).join('');
  if(mood==='happy')return star(22,22,22,palette.cheek)+star(276,20,22,amber);
  if(mood==='proud')return [24,280].map(x=>rect(x,22,16,4,palette.ink)+rect(x,22,4,18,palette.ink)).join('');
  if(mood==='curious')return rect(23,30+phase%2*18,8,34,palette.blue)+rect(285,53-phase%2*18,8,20,palette.blue);
  return [23,289].map(x=>rect(x,28,7,45,palette.blue)+rect(x,176,7,27,palette.blue)).join('');
}
function knockGraphic(mood,signal=false){
  return group(rect(26,24,268,192,amber)+rect(36,34,248,172,dark)+rect(47,45,197,149,panel)+
    rect(56,54,178,7,amber)+rect(56,177,178,7,amber)+rect(237,116,17,20,amber)+
    bang(120,68,30,62,signal?palette.ink:amber)+moodCorners(mood),'data-part="giant-knock-panel"');
}
function warningGraphic(mood,pulse=false,phase=0){
  const c=mood==='grumpy'?palette.red:amber,b=pulse?12:7;
  return group(rect(16,18,288,204,panel)+rect(16+b,18+b,288-2*b,204-2*b,dark)+
    rect(16,18,288,b,c)+rect(16,222-b,288,b,c)+rect(16,18,b,204,c)+rect(304-b,18,b,204,c)+
    bang(pulse?139:144,pulse?47:54,pulse?42:32,pulse?88:76,amber)+
    (pulse?[31,274].map(x=>rect(x,96,15,48,amber)).join(''):'')+moodCorners(mood,phase),'data-part="giant-warning-card"');
}
function bellGraphic(mood,swing=0,ring=false,phase=0){
  const x=160+swing,y=38;
  const bell=at(x-100,y,path('M75 0h50v12h28v18h18v70h13v16h16v20H0v-20h16v-16h13V30h18V12h28Z',amber)+
    rect(42,40,15,59,palette.ink)+rect(60,26,22,12,palette.ink)+rect(88,-13,24,13,palette.prop)+
    rect(83+swing,136,34,17,palette.prop)+rect(92+swing,153,16,7,palette.ink));
  const rays=ring?[0,1,2].map(i=>rect(20+i*10,64+i*32,9,18,amber)+rect(290-i*10,64+i*32,9,18,amber)).join(''):'';
  return group(rect(16,19,288,205,dark)+bell+rays+moodCorners(mood,phase),'data-part="giant-bell"');
}
function requestPlan(asset){
  const spec=requestPerformance(asset),v=asset.variation;
  const beats=spec.hits,signal=Number((beats.at(-1)+.36).toFixed(6));
  const retreat=Number((signal+1.65+(v===3?.18:0)).toFixed(6));
  const poses=[[0,'home']];
  beats.forEach((t,i)=>{
    const lead=Math.min(.16,i?(t-beats[i-1])*.32:t-.02);
    const tail=Math.min(spec.tail||.18,i<beats.length-1?(beats[i+1]-t)*.55:.32);
    poses.push([t-lead,'prepare-'+i],[t-lead*.45,'swing-'+i],[t,'knock-'+i],
      [t+tail*.3,'ripple-'+i],[t+tail*.65,'settle-'+i],[t+tail,'pause']);
  });
  poses.push([signal,'reveal']);
  if(v!==3)poses.push([signal+.24,'ready']);
  if(v===2)poses.push([signal+.85,'pulse'],[signal+1.11,'ready']);
  if(v===3)poses.push([signal+.24,'swing-back'],[signal+.44,'ready'],[signal+.70,'swing-small'],[signal+.92,'ready']);
  poses.push([retreat,'retreat'],[retreat+.18,'leaving'],[retreat+.36,'home'],[asset.seconds,'home']);
  poses.sort((a,b)=>a[0]-b[0]);
  return {beats,signal,retreat,poses};
}
function alertStory(asset,plan){
  const unique=[...new Set(plan.poses.map(p=>p[1]))],v=asset.variation,p=alertProfiles[asset.mood];
  const drawings=unique.map(pose=>{
    if(pose==='home'||pose==='pause')return '';
    if(/^(prepare|swing|knock|ripple|settle)-\d+$/.test(pose))return drawRequestPerformance(asset,pose,plan,p);
    const reveal=pose==='reveal',pulse=reveal||pose==='pulse';
    const swing=reveal?p.recoil*2:pose==='swing-back'?-p.recoil*2:pose==='swing-small'?p.recoil:0;
    const art=v===1?knockGraphic(asset.mood,reveal):v===2?warningGraphic(asset.mood,pulse,pose==='pulse'?1:0):bellGraphic(asset.mood,swing,reveal);
    const y=pose==='retreat'?-48:pose==='leaving'?-168:0;
    return scaleAlert(at(0,y,art));
  });
  return group(unique.map((pose,i)=>{
    const values=plan.poses.map(p=>Number(p[1]===pose)).join(';');
    return group(`<animate attributeName="opacity" values="${values}" keyTimes="${plan.poses.map(p=>Number((p[0]/asset.seconds).toFixed(9))).join(';')}" dur="${asset.seconds}s" begin="0s" repeatCount="indefinite" calcMode="discrete"/>`+drawings[i],`opacity="${i===0?1:0}" data-pose="${pose}"`);
  }).join(''),'data-part="request-alert"');
}
function renderNeedsYou(asset){
  const p=alertProfiles[asset.mood],plan=requestPlan(asset),id='boop-alert-'+asset.mood+'-'+asset.variation;
  const ctx={mood:asset.mood,state:'needs_you',variant:asset.variation,quiet:false,complete:false,motion:true,ink:palette.ink,bg:palette.black,cheek:palette.cheek,suppressDecor:true};
  const spec=requestPerformance(asset);
  const faceBeats=plan.poses.map(([t,pose])=>{
    const i=Number(pose.split('-').at(-1)),dir=Number.isFinite(i)?Math.sign(spec.points[i][0]-160)||1:1;
    const shift=pose.startsWith('prepare-')?[dir,-1]:pose.startsWith('swing-')?[dir*2,-2]:pose.startsWith('knock-')?[dir*2,p.recoil]:pose.startsWith('ripple-')?[-dir,-1]:[0,0];
    return [t,...shift];
  });
  ctx.actorMotion=move(ctx,faceBeats.map(b=>`${b[1]} ${b[2]}`).join(';'),asset.seconds,faceBeats.map(b=>b[0]/asset.seconds).join(';'));
  if(asset.mood==='sad')ctx.tearOverride=rect(79,111,7,9,palette.blue)+rect(232,111,7,9,palette.lightWater);
  const art=face(ctx)+pending()+alertStory(asset,plan);
  // Reduced-motion fallback: a large static alert band and the mood face below.
  const staticArt=scaleAlert(at(0,46,face({...ctx,motion:false,actorMotion:''}))+rect(16,10,288,105,dark)+
    rect(16,10,288,6,amber)+rect(16,109,288,6,amber)+bang(143,24,28,47)+moodCorners(asset.mood));
  return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="${id}" data-mood="${asset.mood}" data-state="needs_you" data-variant="${asset.variation}" data-loop-seconds="${asset.seconds}" data-text-top="192" role="img" aria-labelledby="${id}-title ${id}-desc" shape-rendering="crispEdges" overflow="hidden"><title id="${id}-title">${label(asset.mood)} · ${attrs(asset.name)}</title><desc id="${id}-desc">${attrs(spec.story)} Boop uses ${p.look}, with matching face recoil and material-specific contact sounds. Props and soft paws use large filled pixel surfaces, without cursor marks or detailed hands. The signature ding reveals a large request signal reduced to 80 percent size. The bottom 48 pixels remain clear for text. It reveals Boop again and stays visibly pending. No approval or completion is implied.</desc><defs><clipPath id="${id}-art-area" clipPathUnits="userSpaceOnUse"><rect width="320" height="192"/></clipPath></defs><style>#${id} .alert-still{display:none}@media(prefers-reduced-motion:reduce){#${id} .alert-motion{display:none}#${id} .alert-still{display:inline}}</style><rect width="320" height="240" fill="${palette.black}"/><g data-part="notification-stage" clip-path="url(#${id}-art-area)"><g class="alert-motion">${closeTimelines(art,asset.seconds,'indefinite')}</g><g class="alert-still">${staticArt}</g></g><g data-part="reserved-text-zone" data-y="192" data-height="48"/></svg>\n`;
}
function needsYouScore(asset){
  const p=alertProfiles[asset.mood],plan=requestPlan(asset),spec=requestPerformance(asset),v=asset.variation,events=[];
  // The signature pitch/timbre never changes with mood. Only supporting taps,
  // rhythm and dynamics vary, so questions and approvals share one identity.
  const add=(at,effect,gain,label,pose)=>events.push({at:Number(at.toFixed(6)),effect,gain:Number(gain.toFixed(4)),pitch:effect==='alertDing'?1:p.pitch,label,sync:{part:'request-alert',pose,frame:null}});
  plan.beats.forEach((t,i)=>add(t,spec.effect,p.gain*p.tapGain*(spec.level||1)*(asset.mood==='determined'?1:i%2===0?.95:1),spec.name+' · '+(i+1)+' / '+plan.beats.length,'knock-'+i));
  add(plan.signal,'alertDing',p.gain,'Ding · notification appears','reveal');
  return {id:asset.id,seconds:asset.seconds,policy:'entry',intervalSeconds:0,tailSeconds:0,character:spec.name,
    description:spec.story+' Then the signature ding reveals '+['a large request panel','a pulsing warning card','a gently swinging bell'][v-1]+'. The bottom 20% stays clear for text; the request stays pending.',events};
}

return {alertProfiles,requestLayout,requestPlan,renderNeedsYou,needsYouScore};},
"player.mjs":()=>{
const {makeScene,synthesizeCue,chooseVariation,sceneEvents}=load("bank.mjs");
const {cycleHasSound}=load("score.mjs");
const {sustainedStates}=load("state-catalog.mjs");
const {protectedSoundStates}=load("quiet-mix.mjs");
// Browser/WebView reference player. No network, audio files, or hidden autoplay.
function createBoopPlayer({mount,audioContext=null,volume=.4,onProgress=()=>{},onStatus=()=>{},onCue=()=>{},cacheLimitBytes=8*1024*1024}={}){
  if(!mount)throw new Error('A mount element is required');
  let ctx=audioContext,owned=!audioContext,master=null,session=null,generation=0,raf=0,timer=0,disposed=false,lastPair=null,previousId=null,duck=false;
  const cache=new Map();let cacheBytes=0,scheduled=0,lateSkipped=0;
  const reduced=typeof matchMedia==='function'?matchMedia('(prefers-reduced-motion: reduce)'):null;
  const clamp=x=>Math.max(0,Math.min(.8,Number(x)||0));let level=clamp(volume);
  const report=(phase,extra={})=>onStatus({phase,...extra});
  function draw(t){const svg=mount.querySelector('svg');if(svg){svg.pauseAnimations();svg.setCurrentTime(reduced?.matches?0:t);}}
  function show(id){if(disposed)throw new Error('Player is disposed');const scene=makeScene(id);mount.innerHTML=scene.svg;draw(0);return scene;}
  function audibleTime(){const stamp=ctx.getOutputTimestamp?.();if(stamp?.contextTime>0&&stamp?.performanceTime>0)return Math.min(ctx.currentTime,stamp.contextTime+Math.max(0,performance.now()-stamp.performanceTime)/1000);return Math.max(0,ctx.currentTime-(ctx.outputLatency||0));}
  function stop({clearState=true,notify=true}={}){
    generation++;cancelAnimationFrame(raf);clearInterval(timer);
    const old=session;session=null;
    if(old&&ctx){old.bus.gain.cancelScheduledValues(ctx.currentTime);old.bus.gain.setValueAtTime(old.bus.gain.value,ctx.currentTime);old.bus.gain.linearRampToValueAtTime(0,ctx.currentTime+.018);for(const source of old.sources){try{source.stop(ctx.currentTime+.020);}catch{}}setTimeout(()=>old.bus.disconnect(),50);}
    draw(0);if(clearState)lastPair=null;if(notify)report('stopped');
  }
  async function ready(){
    if(!ctx){const C=globalThis.AudioContext||globalThis.webkitAudioContext;if(!C)throw new Error('Web Audio is unavailable.');ctx=new C();}
    if(!master){master=ctx.createGain();master.gain.value=level;master.connect(ctx.destination);}
    await ctx.resume();if(ctx.state!=='running')throw new Error('Audio needs an enabled user gesture.');
  }
  function key(event,seed){return `${event.effect}:${event.pitch}:${seed}:${ctx.sampleRate}`;}
  function buffer(event,seed){
    const k=key(event,seed);if(cache.has(k)){const b=cache.get(k);cache.delete(k);cache.set(k,b);return b;}
    const samples=synthesizeCue(event,seed,ctx.sampleRate),bytes=samples.byteLength;
    const b=ctx.createBuffer(1,samples.length,ctx.sampleRate);b.copyToChannel(samples,0);
    while(cacheBytes+bytes>cacheLimitBytes&&cache.size){const first=cache.keys().next().value;cacheBytes-=cache.get(first).length*4;cache.delete(first);}
    if(bytes<=cacheLimitBytes){cache.set(k,b);cacheBytes+=bytes;}return b;
  }
  function schedule(s,event,at,cycle){
    if(at<ctx.currentTime-.030){lateSkipped++;return;}
    const source=ctx.createBufferSource(),gain=ctx.createGain();source.buffer=buffer(event,s.seed);gain.gain.value=event.gain;source.connect(gain);gain.connect(s.bus);s.sources.add(source);
    source.onended=()=>{s.sources.delete(source);source.disconnect();gain.disconnect();};
    source.start(Math.max(ctx.currentTime,at));scheduled++;onCue({id:s.scene.asset.id,effect:event.effect,cycle,scheduledAt:at,localAt:event.at,label:event.label});
  }
  function pump(s){
    if(session!==s||!s.scene.score.events.length)return;
    const horizon=ctx.currentTime+.16;
    while(s.cycle<s.cycles){
      if(!cycleHasSound(s.scene.score,s.cycle)){
        if(s.scene.score.policy==='entry'||s.scene.score.policy==='silent')return;
        const stride=Math.max(1,Math.ceil(s.scene.score.intervalSeconds/s.scene.asset.seconds));s.cycle=Math.ceil((s.cycle+1)/stride)*stride;s.event=0;continue;
      }
      const events=eventsFor(s,s.cycle);
      if(!events.length){s.cycle++;s.event=0;continue;}
      const event=events[s.event],at=s.start+s.cycle*s.scene.asset.seconds+event.at;
      if(at>horizon)return;
      schedule(s,event,at,s.cycle);s.event++;
      if(s.event===events.length){s.event=0;s.cycle++;}
    }
  }
  function eventsFor(s,cycle){
    if(!s.eventPlans.has(cycle))s.eventPlans.set(cycle,sceneEvents(s.scene,{cycle,seed:s.seed}));
    while(s.eventPlans.size>4)s.eventPlans.delete(s.eventPlans.keys().next().value);
    return s.eventPlans.get(cycle);
  }
  async function playVariation(id,{cycles=1,seed,preserveState=false}={}){
    if(cycles!==Infinity&&(!Number.isInteger(cycles)||cycles<1||cycles>100))throw new Error('cycles must be 1–100 or Infinity');
    if(disposed)throw new Error('Player is disposed');
    stop({clearState:!preserveState,notify:false});const token=generation,scene=show(id);previousId=id;report('preparing',{id});
    seed=seed??(protectedSoundStates.includes(scene.asset.state)?53:Math.floor(Math.random()*4294967296));
    try{
      await ready();if(token!==generation)return null;
      const candidates=scene.score.mix?.gestures?.flatMap(g=>g.members)||scene.score.events;
      const unique=[...new Map(candidates.map(e=>[key(e,seed),e])).values()];
      for(const event of unique){buffer(event,seed);await new Promise(resolve=>setTimeout(resolve,0));if(token!==generation)return null;}
      const bus=ctx.createGain();bus.gain.value=duck&&!protectedSoundStates.includes(scene.asset.state)?.225:.9;bus.connect(master);
      const s={scene,seed,cycles,start:ctx.currentTime+.09,bus,sources:new Set(),cycle:0,event:0,eventPlans:new Map()};session=s;
      const visualDuration=cycles*scene.asset.seconds,total=visualDuration+scene.score.tailSeconds+.025;
      pump(s);timer=setInterval(()=>pump(s),25);report('playing',{id,scene});
      function tick(){
        if(session!==s)return;
        const elapsed=Math.max(0,audibleTime()-s.start),cycle=Math.floor(elapsed/scene.asset.seconds);
        const local=elapsed>=visualDuration?0:elapsed%scene.asset.seconds;draw(local);
        const sounding=cycleHasSound(scene.score,cycle),cue=sounding?eventsFor(s,cycle).filter(e=>e.at<=local).at(-1):null;
        onProgress({elapsed:Math.min(elapsed,visualDuration),duration:visualDuration,cycle:Math.min(cycles,cycle+1),label:elapsed>=visualDuration?'Home frame':cue?.label|| (scene.score.events.length?'Waiting / quiet':'Intentional silence')});
        if(elapsed<total)raf=requestAnimationFrame(tick);
        else{clearInterval(timer);session=null;draw(0);bus.disconnect();report('finished',{id,scene});}
      }
      raf=requestAnimationFrame(tick);return scene;
    }catch(error){if(token===generation){stop({clearState:false,notify:false});report('error',{message:error.message});}throw error;}
  }
  async function setState(pair,{force=false,seed,hostContext={}}={}){
    const stateKey=pair.mood+':'+pair.state+':'+(hostContext.completionOutcome||'')+':'+(hostContext.startContext||'');
    if(stateKey===lastPair&&!force)return null;
    const id=chooseVariation(pair,{previousId,hostContext});lastPair=stateKey;
    return playVariation(id,{cycles:sustainedStates.includes(pair.state)?Infinity:1,seed,preserveState:true});
  }
  function setVolume(value){level=clamp(value);if(master)master.gain.setTargetAtTime(level,ctx.currentTime,.02);}
  function setSpeechActive(active){duck=!!active;if(session)session.bus.gain.setTargetAtTime(duck&&!protectedSoundStates.includes(session.scene.asset.state)?.225:.9,ctx.currentTime,.035);}
  const visibility=()=>{if(document.hidden)stop();};document.addEventListener('visibilitychange',visibility);
  const pagehide=()=>stop();globalThis.addEventListener('pagehide',pagehide);
  async function dispose(){stop({notify:false});disposed=true;document.removeEventListener('visibilitychange',visibility);globalThis.removeEventListener('pagehide',pagehide);cache.clear();cacheBytes=0;master?.disconnect();if(owned&&ctx)await ctx.close();}
  return {show,playVariation,setState,stop,setVolume,setSpeechActive,dispose,stats:()=>({cacheBytes,cacheEntries:cache.size,scheduled,lateSkipped,activeSources:session?.sources.size||0,playing:!!session})};
}

return {createBoopPlayer};},
"quiet-mix.mjs":()=>{
// Voice-first mix. Keep the accepted animation/cue clocks; omit routine sounds,
// never move a retained sound away from its visible contact. No master-volume hack.
const {random}=load("audio/synth.mjs");
const protectedSoundStates=['needs_you','task_complete','error'];
const silenceStates=['idle','asleep','no_app','listening','waiting'];
const highlightEffects=['snap','snip','glass','bash','landing','wood','latch','key','keyB','keyC','softKey','space','paper','rubber','pop','slide'];
function patternSeed(id,seed,cycle){let h=(seed^Math.imul(cycle+1,2654435761))>>>0;for(const c of id)h=Math.imul(h^c.charCodeAt(0),16777619)>>>0;return h;}
function routineEvents(score,cycle=0,seed=53){
 const mix=score.mix;if(!mix?.gestures)return score.events;
 const rng=random(patternSeed(score.id,seed,cycle)),groups=mix.gestures,chosen=[];let count=0;
 const add=g=>{if(!g||chosen.some(x=>x.group===g)||chosen.length>=4||count>=mix.cueBudget)return;const members=g.members.slice(0,mix.cueBudget-count);chosen.push({group:g,members,gain:.76+rng()*.24});count+=members.length;};
 const keys=groups.filter(g=>['key','keyB','keyC','softKey','space'].includes(g.members[0].effect));
 if(keys.length>=5){
  // A short adjacent run, a gap, then an optional stray contact. Anchors and
  // burst sizes change each cycle; retained presses keep their own releases.
  const length=rng()<.5?2:3,anchor=Math.floor(rng()*Math.max(1,keys.length-length+1));
  for(let i=0;i<length;i++)add(keys[anchor+i]);
  const outside=keys.filter(g=>Math.min(...chosen.map(c=>Math.abs(g.at-c.group.at)))>.55);
  if(outside.length)add(outside[Math.floor(rng()*outside.length)]);
 }else{
  // Preserve the main material action, e.g. the actual SNAP; randomize which
  // supporting contacts are heard, without inventing or delaying impacts.
  const ranked=groups.map(g=>({g,rank:highlightEffects.indexOf(g.members[0].effect)})).sort((a,b)=>(a.rank<0?99:a.rank)-(b.rank<0?99:b.rank));
  const important=ranked.filter(x=>x.rank>=0&&x.rank<=2);
  add(important.length?important[Math.floor(rng()*important.length)].g:groups[Math.floor(rng()*groups.length)]);
  const remaining=groups.map(g=>({g,draw:rng()})).sort((a,b)=>a.draw-b.draw);
  for(const {g}of remaining)if(!chosen.some(c=>Math.abs(c.group.at-g.at)<.075))add(g);
 }
 return chosen.flatMap(c=>c.members.map(e=>({...e,gain:Number((e.gain*.68*c.gain).toFixed(6))}))).sort((a,b)=>a.at-b.at);
}
function quietMix(asset,score){
 if(protectedSoundStates.includes(asset.state))return score;
 const original=score.events.length;
 if(silenceStates.includes(asset.state))return {...score,policy:'silent',intervalSeconds:0,tailSeconds:0,events:[],description:'Intentionally silent in the voice-first mix.',mix:{profile:'voice-first',originalCueCount:original,retainedCueCount:0}};
 if(!original)return score;
 // An early attack plus a release is one physical key gesture. Pair only when
 // the source actually identifies that release; unrelated cues stay independent.
 const groups=[];const used=new Set();
 for(let i=0;i<original;i++){
  if(used.has(i))continue;const e=score.events[i];
  if(e.effect==='release')continue;
  const members=[e];used.add(i);
  if(e.sync?.key==='press'){
   const j=score.events.findIndex((x,k)=>k>i&&x.sync?.key==='release'&&x.sync.beat===e.sync.beat);
   if(j>=0){members.push(score.events[j]);used.add(j);}
  }else if(e.sync?.pose?.startsWith('key-')){
   const j=score.events.findIndex((x,k)=>k>i&&x.sync?.pose==='up-'+e.sync.pose.slice(4));
   if(j>=0){members.push(score.events[j]);used.add(j);}
  }
  groups.push({at:e.at,members});
 }
 const mix={profile:'voice-first',originalCueCount:original,cueBudget:Math.max(1,Math.floor(original*.30)),gestures:groups};
 const events=routineEvents({...score,mix});
 // Very short busy loops leave a silent cycle between their remaining accents.
 // Longer loops already have generous empty space after their few contact cues.
 const sparse=score.policy==='loop'&&asset.seconds<3.5;
 return {...score,events,policy:sparse?'sparse':score.policy,intervalSeconds:sparse?asset.seconds*2:score.intervalSeconds,
  description:'Voice-first: irregular little bursts, pauses and soft accents selected from real visual contacts. '+score.description,
  mix:{...mix,retainedCueCount:events.length,cueReduction:Number((1-events.length/original).toFixed(4)),routineGainMultiplier:.68,accentMultiplierRange:[.76,1],pattern:'seeded clusters, fresh per playback/cycle',silentAlternateCycles:sparse}};
}

return {protectedSoundStates,routineEvents,quietMix};},
"request-performances.mjs":()=>{
const {palette,rect,path,group,at,star}=load("visual/base.mjs");
// Native 320 × 192 action area; the bottom 48 px belongs to host text.
// Each kind is a different performance, not a palette swap of one tap sprite.
const requestPerformances={
  happy:[
    {kind:'pillow',name:'Friendly pillow pats',hits:[.42,1.02],points:[[56,165],[264,165]],effect:'alertSoftTap',story:'Two broad soft pats alternate left and right, with a happy bounce.'},
    {kind:'envelope',name:'Bouncy invitation',hits:[.44,.84,1.24],points:[[64,159],[160,151],[256,159]],effect:'alertPaperTap',story:'An invitation envelope hops across the glass and opens its flap.'},
    {kind:'gift',name:'A little delivery',hits:[.56,1.18],points:[[148,151],[180,151]],effect:'alertSoftTap',story:'A little parcel bumps the glass; its lid pops up to reveal a request card.'}
  ],
  excited:[
    {kind:'pinball',name:'Everywhere at once',hits:[.26,.44,.62,.80,.98,1.16],points:[[42,74],[272,151],[276,72],[44,155],[160,164],[160,69]],effect:'alertSoftTap',story:'Six rapid, broad pats jump around the screen, with a fading trail.'},
    {kind:'ball',name:'Ricochet hello',hits:[.28,.50,.72,.94,1.16],points:[[46,105],[136,164],[274,94],[236,164],[160,69]],effect:'alertRubberTap',story:'A chunky ball ricochets across the glass, squashing at each impact.'},
    {kind:'cord',name:'Overeager alert cord',hits:[.32,.54,.76,1.08],points:[[274,111],[274,137],[274,117],[274,146]],effect:'alertRubberTap',story:'Boop repeatedly yanks an oversized pull-cord; its soft knob springs back.'}
  ],
  proud:[
    {kind:'stamp',name:'Royal summons',hits:[.56,1.20],points:[[96,159],[224,159]],effect:'alertKnock',story:'A grand stamp lands twice, leaving a bold request seal rather than an approval check.'},
    {kind:'cane',name:'Gentlemanly cane tap',hits:[.56,1.30],points:[[52,167],[68,167]],effect:'alertKnock',story:'A chunky hooked cane lifts and taps the glass with theatrical composure.'},
    {kind:'curtain',name:'Ahem, spotlight',hits:[.50,1.18],points:[[52,139],[268,139]],effect:'alertSoftTap',story:'Two curtains sweep inward with soft thumps, then part to present Boop.'}
  ],
  curious:[
    {kind:'lens',name:'Inspect the glass',hits:[.46,.94,1.34],points:[[48,83],[264,103],[164,143]],effect:'alertKnock',story:'An oversized magnifying glass inspects three places, bumping its rim against the glass.'},
    {kind:'keycap',name:'Is this the button?',hits:[.48,.94,1.28],points:[[60,161],[160,161],[260,161]],effect:'alertKeyboardTap',story:'A giant question-mark keycap probes different spots, compressing on each press.'},
    {kind:'periscope',name:'Who is out there?',hits:[.48,1.02,1.40],points:[[92,112],[228,96],[180,70]],effect:'alertKnock',story:'A chunky periscope extends, changes direction and nudges the screen.'}
  ],
  determined:[
    {kind:'palms',name:'Steady two-paw request',hits:[.32,.64,.96],points:[[136,166],[160,166],[184,166]],effect:'alertKnock',story:'Two simple soft pads press in lockstep: three firm, even beats.'},
    {kind:'press',name:'Press the request',hits:[.38,.68,.98],points:[[160,164],[160,164],[160,164]],effect:'alertKeyboardTap',story:'A chunky plunger presses a large request button three times with mechanical precision.'},
    {kind:'blocks',name:'Build a step',hits:[.36,.68,1.00],points:[[56,166],[56,126],[56,86]],effect:'alertKnock',story:'Three big blocks stack upward so Boop can reach higher and demand attention.'}
  ],
  grumpy:[
    {kind:'keyboard',name:'Keyboard ultimatum',hits:[.34,.60,.84,1.08],points:[[106,160],[212,153],[126,160],[204,153]],effect:'alertKeyboardTap',story:'Boop brandishes a keyboard side to side, then bashes its broad face against the glass.'},
    {kind:'brick',name:'Brick negotiation',hits:[.44,.74,1.12],points:[[110,152],[206,156],[158,152]],effect:'alertBrickTap',story:'A big brick winds up and thumps the glass; chunky stress marks appear and clear.'},
    {kind:'tantrum',name:'Two-paw tantrum',hits:[.25,.43,.61,.79,1.06],points:[[48,163],[272,163],[48,163],[272,163],[160,163]],effect:'alertKnock',story:'Heavy broad pats alternate sides, ending with a simultaneous two-paw shove.'}
  ],
  sad:[
    {kind:'poke',name:'Is anybody there?',hits:[.70,1.70],points:[[268,166],[252,161]],effect:'alertSoftTap',level:.80,tail:.30,story:'One simple soft puff hesitates, makes two light pokes, then retreats.'},
    {kind:'lean',name:'Please notice me',hits:[.74,1.86],points:[[160,153],[160,153]],effect:'alertSoftTap',level:.85,tail:.34,story:'Two soft pads press and slowly slip down the glass while Boop waits tearfully.'},
    {kind:'tissue',name:'Tissue-box plea',hits:[.84,1.96],points:[[244,151],[260,155]],effect:'alertPaperTap',level:.75,tail:.32,story:'A tissue rises from a little box, pats the glass and folds back down.'}
  ]
};

function requestPerformance(asset){return requestPerformances[asset.mood][asset.variation-1];}
const white=palette.ink,blue=palette.blue,coral=palette.cheek,amber=palette.amber,black=palette.black;
const chunky=(x,y,w,h,c=white)=>at(x-w/2,y-h/2,rect(8,0,w-16,h,c)+rect(0,8,w,h-16,c));
function contact(x,y,phase,force=1){
  const w=8*Math.round(5+force*2)-(phase===2?8:0),h=phase===0?24:32;
  return group(chunky(x,y,w,h),`data-part="tap-surface" data-cell="8" opacity="${phase===0?.92:phase===1?.5:.22}"`);
}
function smallBoard(x,y,w=96,h=32){
  return at(x-w/2,y-h/2,rect(0,0,w,h,palette.prop)+rect(8,4,w-16,h-8,black)+
    [0,1,2,3,4,5].map(i=>rect(12+i*12,8,8,8,white)).join('')+rect(24,h-12,w-48,8,white));
}
function brick(x,y,w=72,h=32){
  return at(x-w/2,y-h/2,rect(0,0,w,h,coral)+rect(0,0,w,8,'#FF9E9A')+
    rect(0,h/2,w,6,'#B95060')+rect(w/3,8,6,h/2-8,'#B95060')+rect(w*2/3,h/2,6,h/2,'#B95060'));
}
function envelope(x,y,open=false){
  return at(x-32,y-20,rect(0,8,64,32,white)+path(open?'M0 8h16V0h32v8h16v8H0Z':'M0 8h16v8h16v8h16v-8h16v-8H0Z',blue)+rect(24,24,16,8,coral));
}
function questionKey(x,y,hit){
  return at(x-28,y-(hit?16:24),chunky(28,hit?16:24,56,hit?32:48,white)+
    path('M16 8h24v8h-8v8h-8V16h-8ZM24 28h8v8h-8Z',blue));
}

// All special effects remain composed of chunky filled surfaces or 8 px blocks.
function drawRequestPerformance(asset,pose,plan,profile){
  const spec=requestPerformance(asset),index=Number(pose.split('-').at(-1));
  const stage=pose.startsWith('prepare-')?-2:pose.startsWith('swing-')?-1:pose.startsWith('knock-')?0:pose.startsWith('ripple-')?1:2;
  const hit=stage===0,after=stage>0,phase=Math.max(0,stage),last=index===spec.hits.length-1;
  const target=spec.points[index],previous=spec.points[Math.max(0,index-1)];
  const blend=stage===-2?.45:stage===-1?.8:1;
  const x=Math.round(previous[0]+(target[0]-previous[0])*blend);
  const y=Math.round(previous[1]+(target[1]-previous[1])*blend)+(stage<0?-16:stage===1?-4:0);
  const pad=(px=x,py=y,force=profile.impact)=>contact(px,py,phase,force);
  const lift=stage===-2?-24:stage===-1?-12:stage===1?-8:0;
  let art='';
  switch(spec.kind){
    case 'pillow':
      art=stage<0?chunky(x,y,32,40):pad();
      if(hit)art+=star(x+(index%2?-36:36),y-24,16,coral);
      break;
    case 'envelope':art=envelope(x,y+lift,last&&after)+(hit?group(pad(), 'opacity=".16"'):'');break;
    case 'gift':{
      const lid=last&&after?-24:stage<0?-8:0;
      art=at(x-32,y-16,rect(0,0,64,32,blue)+rect(24,0,16,32,white)+rect(-8,-8+lid,80,8,coral)+rect(16,-24+lid,16,16,coral)+rect(32,-24+lid,16,16,coral));
      if(last&&after)art+=at(x-12,y-34,rect(0,0,24,24,white)+rect(8,0,8,12,amber)+rect(8,16,8,8,amber));
      break;
    }
    case 'pinball':
      if(index>0)art+=group(contact(previous[0],previous[1],2,profile.impact),'opacity=".4"');
      art+=stage<0?chunky(x,y,32,32):pad();break;
    case 'ball':
      if(index>0)art+=[.35,.65].map(f=>rect(Math.round(previous[0]+(x-previous[0])*f)-4,Math.round(previous[1]+(y-previous[1])*f)-4,8,8,blue)).join('');
      art+=chunky(x,y,hit?64:40,hit?24:40,blue)+rect(x-8,y-8,16,8,white);break;
    case 'cord':art=rect(270,40,8,Math.max(8,y-40),white)+chunky(274,y,hit?56:40,hit?24:40,coral);break;
    case 'stamp':
      if(after)art+=at(x-24,y-12,rect(0,0,48,24,amber)+rect(16,0,8,12,black)+rect(16,16,8,8,black));
      art+=at(x-32,y-24+lift,rect(20,-24,24,24,blue)+rect(8,0,48,16,palette.prop)+rect(0,16,64,16,white));break;
    case 'cane':art=at(x-8,y-64+lift,path('M0 0h32v8h8v16h-8V8H8v56H0Z',amber))+(hit?pad(x,y,.9):'');break;
    case 'curtain':{
      const w=hit?88:stage<0?56:32;
      art=[8,312-w].map(cx=>rect(cx,48,w,120,coral)+rect(cx+8,48,8,120,'#B95060')+rect(cx+w-16,48,8,120,'#B95060')).join('');
      if(hit)art+=pad(index%2?248:72,164);break;
    }
    case 'lens':art=at(x-28,y-28+lift,chunky(28,28,56,56,blue)+rect(12,12,32,32,black)+rect(20,20,16,8,white)+rect(40,48,16,24,white));break;
    case 'keycap':art=questionKey(x,y+lift,hit);break;
    case 'periscope':art=rect(152,Math.min(y,176),16,Math.max(8,176-y))+rect(Math.min(160,x),y-8,Math.max(16,Math.abs(x-160)),16,blue)+chunky(x,y,40,32,blue)+rect(x-8,y-8,16,16,white)+rect(136,176,48,8,palette.prop);break;
    case 'palms':art=pad(x-40,y)+pad(x+40,y);break;
    case 'press':art=rect(112,172,96,12,blue)+chunky(160,160,72,24,amber)+rect(152,108+lift,16,hit?48:32,white)+chunky(160,108+lift,64,24,blue);break;
    case 'blocks':
      for(let i=0;i<index;i++)art+=at(36,150-i*40,rect(0,0,40,32,blue)+rect(8,8,24,8,white));
      art+=at(x-20,y-16+lift,rect(0,0,40,32,hit?white:blue)+rect(8,8,24,8,hit?blue:white));break;
    case 'keyboard':
      art=smallBoard(x+(stage<0?(index%2?20:-20):0),y+lift,hit?112:96,hit?32:24);
      if(after)art+=rect(x-64,y-20,8,8,white)+rect(x+56,y-28,8,8,white);
      if(hit)art+=group(pad(x,y,1.4),'opacity=".25"');break;
    case 'brick':
      art=brick(x+(stage<0?(index%2?28:-28):0),y+lift,hit?88:72,32);
      if(hit||stage===1)art+=path(`M${x-48} ${y-20}h-16v-16h-8v24h24ZM${x+40} ${y+8}h24v16h8V${y}h-32Z`,white);
      break;
    case 'tantrum':
      art=last?pad(56,164,1.4)+pad(264,164,1.4):stage<0?chunky(x,y,40,40):pad(x,y,1.4);
      if(hit)art+=rect(index%2?24:288,100,8,8,palette.prop)+rect(index%2?32:280,84,8,8,palette.prop);break;
    case 'poke':art=chunky(x,y+(stage<0?16:after?phase*4:0),hit?40:32,hit?24:32,white);break;
    case 'lean':{
      const slip=stage<0?0:phase*8;art=chunky(64,153+slip,hit?56:40,24)+chunky(256,153+slip,hit?56:40,24);
      art+=rect(84,133+slip,8,8,blue)+rect(232,125+slip,8,8,palette.water);break;
    }
    case 'tissue':{
      art=at(208,160,rect(0,0,72,24,blue)+rect(8,0,56,8,black));
      const h=hit?40:stage===2?24:48;
      art+=at(x-20,y-h+16+(stage<0?8:0),path(`M8 0h24v8h8v${h-16}h-8v8H8v-8H0V8h8Z`,white)+rect(8,h-16,24,8,palette.prop));
      if(after)art+=rect(x+24,y-8,8,8,blue);break;
    }
    default:throw new Error('Unknown request performance '+spec.kind);
  }
  return group(art,`data-part="request-performance" data-kind="${spec.kind}" data-stage="${stage}" data-target-x="${target[0]}" data-target-y="${target[1]}"${stage===2?' opacity=".55"':''}`);
}

return {requestPerformances,requestPerformance,drawRequestPerformance};},
"score.mjs":()=>{
const {keyPlans}=load("keyboard.mjs");
const {tracksFromSVG,entrances}=load("timing.mjs");
const {effects}=load("audio/effects.mjs");
const {needsYouScore}=load("needs-you.mjs");
const moodSound={
  happy:{pitch:1,gain:.75,character:'warm, light and buoyant'},
  excited:{pitch:1.10,gain:.86,character:'bright, brisk and springy'},
  proud:{pitch:.96,gain:.77,character:'deliberate, polished and theatrical'},
  curious:{pitch:1.045,gain:.64,character:'small tactile discoveries with pauses'},
  determined:{pitch:.98,gain:.79,character:'precise, planted and evenly accented'},
  grumpy:{pitch:.94,gain:.88,character:'brittle cracks and impatient material noises'},
  sad:{pitch:.93,gain:.58,character:'soft, damp and persistently trying'}
};
const directions={
  conveyor:'Dry roller clicks; little parcel landings on the belt.',
  piano:'Ivory-key clacks, not a tune; each visible key change gets a light press.',
  'paper-plane':'Paper crease, fold, airy launch and a fresh-page shuffle.',
  'block-tower':'Increasing stacks of woody cube clicks; a short delivery slide.',
  stamp:'One broad stamp clack, light rebound and paper sliding out.',
  turbo:'Ten synchronized presses per second, with quieter release ticks.',
  juggle:'Soft catches and short air swishes around the cube orbit.',
  rocket:'Short jet pulses follow the keyboard lift and descent; a light landing.',
  treadmill:'Quick roller ratchets and passing-card flutters, not background music.',
  pinball:'Dry bumper contacts and tiny spring recoils at each new position.',
  pedestal:'Small lift-motor strokes, a latch and a restrained sparkle.',
  conductor:'Baton air swishes answered by shuffling cards; no orchestral backing.',
  origami:'Two crisp paper folds, a reveal flutter and a delivery slide.',
  polish:'Alternating cloth buffs, a small shine accent, then quiet.',
  'one-key':'One exaggerated mechanical key clack, release and loose-key rattle.',
  magnifier:'Quiet lens-housing slides with tiny position-stop clicks.',
  periscope:'Telescoping tube ratchets and a small extension stop.',
  explode:'Four-piece separation clicks followed by a clean reassembly snap.',
  maze:'Sparse tactile ticks at the square’s turns; no repeating scanner beep.',
  box:'Lid creak, opening latch, small discovery accent and lid settling.',
  steady:'Approved crisp 6.7-press/second keyboard rhythm; matched release clicks.',
  uphill:'Gritty cube scrapes and short landings on each step.',
  'brick-wall':'Paired brick placements, with different-size block resonances.',
  winch:'Crank ratchets and tiny tension creaks on each visible lift.',
  scissors:'Blade movement, one sharp snip, severed-fibre flutter and reopening.',
  'key-rain':'Approved brittle keyboard fractures and scattered keycaps on every downstroke.',
  snap:'Three accelerating fractures, strain, SNAP, falling halves and resumed typing.',
  throw:'Desk fracture, three glassy screen cracks, throw, wipes and replacement keys.',
  crumple:'Three fast paper scrunch–squeeze–throw sequences, then a fresh sheet.',
  boiler:'Rapid metal lid rattle, two steam bursts, lid launch and clattering landing.',
  flood:'Approved soft rhythmic typing, cube-water drops, splashes and a tiny short circuit.',
  buckets:'Bucket pings, clustered water drops, overflow and a draining gurgle.',
  tissue:'Dry feed-motor ticks and accordion-paper rustles; soft pull-away.',
  umbrella:'Rain-like cube patters on the canopy and splashes down the sides.',
  raft:'Small water sloshes track the raft; a soft deck creak on the low bob.'
};

function composeScore(asset,svg){
  if(asset.state==='needs_you')return needsYouScore(asset);
  const {mood,state,variation:v,action,seconds}=asset,profile=moodSound[mood];
  const tracks=tracksFromSVG(svg),events=[];
  let description='',policy='loop',intervalSeconds=0;
  const add=(at,effect,gain=.7,label=effect,pitch=1,sync=null)=>{
    if(at<0||at>=seconds-.02)return;
    if(!effects[effect])throw new Error('Unknown effect '+effect);
    events.push({at:Number(at.toFixed(6)),effect,gain:Number(gain.toFixed(4)),pitch,label,...(sync?{sync}:{})});
  };
  const frameCue=(entry,effect,gain=.7,label=effect,pitch=1)=>add(entry.at,effect,gain,label,pitch,{part:entry.part,frame:entry.frame,pose:entry.pose});
  const part=action?'story-'+action:null;
  const entries=part?entrances(tracks,part):[];
  const frame=(index,effect,gain=.7,label=effect)=>entries.filter(e=>e.frame===index).forEach(e=>frameCue(e,effect,gain,label));
  const firstFrame=(index,effect,gain=.7,label=effect)=>{const e=entries.find(e=>e.frame===index);if(e)frameCue(e,effect,gain,label);};

  if(['asleep','no_app'].includes(state)){
    policy='silent';description='Intentional silence · shared quiet routine · no simulated breathing or snores.';
  }else if(state==='idle'){
    policy=v===1?'silent':'sparse';intervalSeconds=45;
    description=v===1?'Intentional silence · breathing and blinking stay visual.':v===2?'A tiny cloth-like glance accent; at most once per 45 seconds.':'A soft movement swish and cushion landing; at most once per 45 seconds.';
    const tr=tracks.find(t=>t.part===(v===2?'gaze':'face')&&t.attribute==='transform');
    const beats=tr?tr.times.filter((time,i)=>i>0&&tr.values[i]!==tr.values[i-1]&&time<seconds-.5):[];
    if(v===2&&beats.length)add(beats[0],'cloth',.20,'Quiet glance',profile.pitch);
    if(v===3&&beats.length){add(beats[0],'swipe',.20,'Small stretch',profile.pitch);if(beats[1])add(beats[1],'cushion',.32,'Settle',profile.pitch);}
  }else if(state==='listening'){
    policy=v===1?'silent':'entry';
    description=v===1?'Silent focused listening; no beeps compete with the user.':v===2?'One soft headset-settling click on entry; silent while listening.':'One light prop-handling brush on entry; silent while listening.';
    if(v===2){add(.06,'cushion',.24,'Headset settles',profile.pitch);add(.09,'latch',.16,'Soft fit click',profile.pitch);}
    if(v===3)add(.08,'cloth',.22,'Trumpet settles',profile.pitch);
  }else if(state==='task_complete'){
    policy='entry';
    const pitch=({happy:1,excited:1.06,proud:.94,curious:1.03,determined:.98,grumpy:.91,sad:.96})[mood];
    if(v===1){
      const fx=['excited','proud'].includes(mood)?'trophyB':'trophyA';
      add(.08,fx,mood==='sad'?.72:.86,'Victory fanfare',pitch);
      description=`${effects[fx].duration.toFixed(2)} s layered trophy fanfare with synthesized ${fx==='trophyB'?'crowd-like cheer and applause':'applause'}; then room for a mumble.`;
    }else if(v===2){
      const beats=entrances(tracks,'curtain-reveal');
      const close=beats.find(e=>e.frame===1),open=beats.find(e=>e.frame===4);
      if(close)frameCue(close,'cloth',.34,'Curtains gather');
      if(open)frameCue(open,'swipe',.30,'Curtains part');
      const start=Math.max(.08,(open?.at||1.08)-.47);
      add(start,'trophyB',mood==='sad'?.64:.82,'Curtain-call fanfare',pitch);
      description='2.85 s theatrical reveal fanfare, cloth swish and synthesized crowd-like applause. No spoken words.';
      if(mood==='proud')description+=' MWHAHAHA lettering reserves a future voice layer; no fake speech added.';
    }else{
      const beats=entrances(tracks,'podium-rise'),lift=beats.find(e=>e.frame===1);
      add(lift?.at||.8,'victoryPodium',mood==='sad'?.69:.86,'Podium fanfare',pitch);
      for(const e of beats.filter(e=>[1,2,3].includes(e.frame)&&e.at<3))frameCue(e,'ratchet',.22,'Podium lift');
      description='2.65 s rising podium fanfare; the full chord lands at the top step, with synthesized applause.';
    }
  }else if(state==='working'){
    description=directions[action];if(!description)throw new Error('No sound design for '+action);
    const plan=keyPlans[action];
    if(plan){
      plan.presses.forEach((at,i)=>{
        const fx=action==='key-rain'?'bash':action==='flood'?'softKey':['key','keyB','keyC','space'][i%4];
        const gain=action==='key-rain'?(i%2?.94:.81):action==='flood'?.77:(i%4===0?.95:.78);
        add(at,fx,gain,action==='key-rain'?'Keyboard fractures':'Key press',1,{key:'press',beat:i});
        add(at+plan.hold,'release',action==='flood'?.37:.55,'Key release',1,{key:'release',beat:i});
        if(action==='key-rain')add(at+.10,'keycap',.48,'Loose key scatter');
      });
      if(action==='flood'){
        for(let i=0;i<22;i++)add(.085+i*.281,'drop',.25+(i%4)*.06,'Cube water');
        for(const at of [.39,.98,1.62,2.32,2.91,3.57,4.20,4.82,5.40,5.96])add(at,'splash',at>2.8&&at<4.5?.64:.39,'Water splash');
        add(3.328,'short',.8,'Tiny short circuit');
      }
    }else if(['snap','throw','crumple','boiler'].includes(action)){
      for(const e of entries){const pose=e.pose;
        if(action==='snap'){
          if(pose.startsWith('slam'))frameCue(e,'bash',[.8,.92,1][Number(pose.at(-1))-1],'Bash / fracture');
          if(pose==='strain')frameCue(e,'creak',.75,'Strain');
          if(pose==='crack')frameCue(e,'snap',1,'SNAP');
          if(pose==='fly')frameCue(e,'whoosh',.7,'Halves fly');
          if(pose==='fallen'){frameCue(e,'landing',.78,'Plastic fragments land');add(e.at+.08,'keycap',.46,'Loose key');add(e.at+.185,'keycap',.30,'Loose key');}
          if(pose==='reload')frameCue(e,'landing',.25,'Replacement keyboard');
        }else if(action==='throw'){
          if(pose==='desk')frameCue(e,'bash',.90,'Desk fracture');
          if(pose.startsWith('screen')){frameCue(e,'glass',.7+Number(pose.at(-1))*.09,'Screen crack '+pose.at(-1));add(e.at+.045,'snap',.47,'Plastic shell cracks');}
          if(pose==='release')frameCue(e,'swipe',.95,'Keyboard thrown');
          if(pose==='exit')frameCue(e,'keycap',.36,'Fragments exit');
          if(pose.startsWith('wipe'))frameCue(e,'cloth',.42,'Wipe cracks away');
          if(pose==='reload')frameCue(e,'landing',.38,'Replacement keyboard');
        }else if(action==='crumple'){
          if(pose.startsWith('scrunch'))frameCue(e,'crumple',.91,'Crumple paper');
          if(pose.startsWith('squeeze'))frameCue(e,'tear',.63,'Squeeze');
          if(pose.startsWith('ball'))frameCue(e,'paper',.45,'Tight paper ball');
          if(pose.startsWith('toss'))frameCue(e,'swipe',.65,'Throw paper');
          if(pose.startsWith('edge'))frameCue(e,'cushion',.52,'Paper lands');
          if(pose==='feed')frameCue(e,'paper',.60,'Fresh page');
        }else{
          if(['left','right'].includes(pose))frameCue(e,'metal',.43,'Lid rattles');
          if(pose.startsWith('puff'))frameCue(e,'steam',pose==='puff1'?.75:1,'Steam burst');
          if(pose==='launch'){frameCue(e,'pop',.8,'Lid launches');add(e.at+.025,'steam',.84,'Pressure escapes');}
          if(pose==='land')frameCue(e,'metal',.92,'Lid lands');
          if(pose==='bounce')frameCue(e,'metal',.49,'Lid rebounds');
        }
        if(['snap','throw'].includes(action)&&pose==='tap'){
          frameCue(e,'key',.86,'Back to typing');
          const up=entries.find(x=>x.at>e.at&&x.pose==='ready');if(up)frameCue(up,'release',.55,'Key release');
        }
      }
    }else{
      // Each action has its own material, rhythm and foreground gesture. Every
      // primary cue below is attached to a real compiled SVG frame transition.
      switch(action){
        case 'conveyor':for(const e of entries.filter(e=>e.frame>0&&e.frame%2===0))frameCue(e,'latch',e.frame%6===0?.44:.25,'Roller click');for(const e of entries.filter(e=>[6,14,22,28].includes(e.frame)))frameCue(e,'wood',.40,'Parcel lands');break;
        case 'piano':entries.filter(e=>e.frame<=4).forEach((e,i)=>{frameCue(e,['keyB','keyC','key','space'][i%4],.60,'Ivory key clack');add(e.at+.06,'release',.31,'Key returns');});break;
        case 'paper-plane':frame(1,'fold',.77,'Paper crease');frame(2,'fold',.54,'Last fold');frame(3,'swipe',.73,'Plane launches');firstFrame(8,'paper',.50,'Fresh sheet');break;
        case 'block-tower':for(let i=1;i<=4;i++)frame(i,'wood',.48+i*.055,'Cube placed');firstFrame(5,'slide',.42,'Tower delivered');break;
        case 'stamp':frame(1,'creak',.33,'Stamp descends');frame(2,'wood',.94,'Stamp lands');frame(3,'latch',.35,'Stamp releases');firstFrame(5,'paper',.58,'Card slides out');break;
        case 'juggle':for(const e of entries.filter(e=>e.frame>0&&e.frame%3===0))frameCue(e,e.frame%6?'swipe':'rubber',e.frame%6?.20:.47,e.frame%6?'Cube travels':'Soft catch');break;
        case 'rocket':for(let i=1;i<=3;i++)frame(i,'jet',i===2?.80:.51,'Jet pulse');frame(4,'landing',.38,'Keyboard lands');break;
        case 'treadmill':for(const e of entries.filter(e=>e.frame>0&&e.frame%3===0))frameCue(e,e.frame%6?'paper':'ratchet',e.frame%6?.40:.46,e.frame%6?'Card passes':'Roller turns');break;
        case 'pinball':for(let i=1;i<=4;i++){frame(i,'latch',.62,'Bumper contact');frame(i,'rubber',.29,'Spring recoil');}break;
        case 'pedestal':frame(1,'motor',.48,'Workstation rises');frame(2,'latch',.49,'Platform locks');frame(2,'shimmer',.34,'Show-off sparkle');frame(4,'motor',.32,'Platform lowers');break;
        case 'conductor':entries.filter(e=>e.frame<=4).forEach((e,i)=>{frameCue(e,'swipe',.32,'Baton flourish');if(i%2===0)frameCue(e,'paper',.34,'Cards shuffle');});break;
        case 'origami':frame(1,'fold',.73,'Diagonal fold');frame(2,'fold',.62,'Crane takes shape');frame(3,'paper',.34,'Wing flutter');firstFrame(5,'swipe',.36,'Crane delivered');break;
        case 'polish':entries.filter(e=>e.frame<=4).forEach(e=>frameCue(e,'cloth',.53,'Buffing stroke'));firstFrame(3,'shimmer',.34,'Polished shine');break;
        case 'one-key':frame(1,'creak',.36,'Key anticipation');frame(2,'space',1,'Giant key press');frame(3,'release',.73,'Key releases');frame(3,'keycap',.28,'Cap settles');break;
        case 'magnifier':entries.filter(e=>e.frame<=4).forEach((e,i)=>frameCue(e,i%2?'latch':'slide',i%2?.24:.21,'Lens adjusts'));break;
        case 'periscope':frame(1,'ratchet',.48,'Tube extends');frame(2,'ratchet',.60,'Tube extends');frame(3,'latch',.33,'Eye pivots');frame(4,'slide',.41,'Tube lowers');break;
        case 'explode':frame(1,'pop',.51,'Cube separates');frame(2,'latch',.55,'Pieces extend');frame(3,'slide',.35,'Pieces return');frame(4,'latch',.70,'Cube reassembled');break;
        case 'maze':entries.filter(e=>e.frame<=4).forEach((e,i)=>frameCue(e,i%2?'keyB':'latch',.26,'Square turns'));break;
        case 'box':frame(1,'creak',.60,'Lid lifts');frame(2,'latch',.48,'Box opens');frame(2,'shimmer',.28,'Small discovery');frame(4,'wood',.42,'Lid settles');break;
        case 'uphill':for(let i=1;i<=4;i++){frame(i,'slide',.59,'Cube scrapes uphill');frame(i,'wood',.35,'Next step');}firstFrame(5,'swipe',.34,'Load delivered');break;
        case 'brick-wall':for(let i=1;i<=4;i++){frame(i,'wood',.59,'Bricks placed');const e=entries.find(e=>e.frame===i);if(e)add(e.at+.044,'wood',.35,'Second brick settles',1.12);}firstFrame(5,'slide',.38,'Wall slides out');break;
        case 'winch':entries.filter(e=>e.frame<=4).forEach(e=>{frameCue(e,'ratchet',.57,'Crank turns');frameCue(e,'creak',.24,'Rope tension');});break;
        case 'scissors':frame(1,'metal',.27,'Blades poise');frame(2,'snip',.89,'SNIP');frame(2,'tear',.44,'Strip parts');frame(4,'metal',.31,'Blades open');break;
        case 'buckets':for(let i=1;i<=4;i++){frame(i,'drop',.50,'Bucket fills');if(i%2===0)frame(i,'metal',.19,'Water hits bucket');}frame(3,'splash',.56,'Overflow');frame(4,'splash',.66,'Overflow');firstFrame(5,'bubble',.59,'Drain');firstFrame(7,'splash',.35,'Water recedes');break;
        case 'tissue':for(let i=1;i<=4;i++){frame(i,'motor',.36,'Printer advances');frame(i,'paper',.42,'Tissue unfolds');}firstFrame(5,'tear',.41,'Tissue pulls free');firstFrame(8,'paper',.27,'Tissue clears');break;
        case 'umbrella':for(let i=1;i<=4;i++){frame(i,'sprinkle',.52,'Rain hits canopy');frame(i,'splash',.27,'Side splash');}break;
        case 'raft':for(let i=1;i<=4;i++)frame(i,'splash',i===3?.50:.29,'Raft sloshes');frame(3,'creak',.30,'Deck creaks');break;
        default:throw new Error('Unscored action '+action);
      }
    }
  }else throw new Error('Unscored state '+state);

  events.sort((a,b)=>a.at-b.at);
  const tail=Math.max(0,...events.map(e=>e.at+effects[e.effect].duration-seconds));
  return {id:asset.id,seconds,policy,intervalSeconds,description,character:profile.character,tailSeconds:Number(tail.toFixed(6)),events};
}

function cycleHasSound(score,cycle){
  if(score.policy==='silent')return false;
  if(score.policy==='entry')return cycle===0;
  if(score.policy==='sparse')return cycle%Math.max(1,Math.ceil(score.intervalSeconds/score.seconds))===0;
  return true;
}

return {moodSound,composeScore,cycleHasSound};},
"state-art.mjs":()=>{
const {palette:P,rect,path,group,at,face,star,keycap,victoryBackground,trophy}=load("visual/base.mjs");
const {closeTimelines}=load("visual/loop.mjs");
const {acting,sustainedStates}=load("state-catalog.mjs");
const {effects}=load("audio/effects.mjs");
const GREEN='#83D99A',DEEP='#244634';
const safe=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const n=x=>Number(x.toFixed(6));
const glyph={
 A:'01110 10001 10001 11111 10001 10001 10001',B:'11110 10001 10001 11110 10001 10001 11110',C:'01111 10000 10000 10000 10000 10000 01111',D:'11110 10001 10001 10001 10001 10001 11110',E:'11111 10000 10000 11110 10000 10000 11111',F:'11111 10000 10000 11110 10000 10000 10000',G:'01111 10000 10000 10111 10001 10001 01111',H:'10001 10001 10001 11111 10001 10001 10001',I:'11111 00100 00100 00100 00100 00100 11111',J:'00111 00010 00010 00010 10010 10010 01100',K:'10001 10010 10100 11000 10100 10010 10001',L:'10000 10000 10000 10000 10000 10000 11111',M:'10001 11011 10101 10101 10001 10001 10001',N:'10001 11001 10101 10011 10001 10001 10001',O:'01110 10001 10001 10001 10001 10001 01110',P:'11110 10001 10001 11110 10000 10000 10000',Q:'01110 10001 10001 10001 10101 10010 01101',R:'11110 10001 10001 11110 10100 10010 10001',S:'01111 10000 10000 01110 00001 00001 11110',T:'11111 00100 00100 00100 00100 00100 00100',U:'10001 10001 10001 10001 10001 10001 01110',V:'10001 10001 10001 10001 10001 01010 00100',W:'10001 10001 10001 10101 10101 10101 01010',X:'10001 10001 01010 00100 01010 10001 10001',Y:'10001 10001 01010 00100 00100 00100 00100',Z:'11111 00001 00010 00100 01000 10000 11111',
 '0':'01110 10001 10011 10101 11001 10001 01110','1':'00100 01100 00100 00100 00100 00100 01110','2':'01110 10001 00001 00010 00100 01000 11111','3':'11110 00001 00001 01110 00001 00001 11110','!':'00100 00100 00100 00100 00100 00000 00100','>':'10000 01000 00100 00010 00100 01000 10000','+':'00000 00100 00100 11111 00100 00100 00000','(':'00010 00100 01000 01000 01000 00100 00010',')':'01000 00100 00010 00010 00010 00100 01000','_':'00000 00000 00000 00000 00000 00000 11111',' ':'00000 00000 00000 00000 00000 00000 00000'
};
function pixelText(text,x,y,size=2,color=P.ink){
 let art='';for(const [i,c]of[...text].entries())for(const [row,bits]of(glyph[c.toUpperCase()]||glyph[' ']).split(' ').entries())for(let col=0;col<5;col++)if(bits[col]==='1')art+=rect(x+(i*6+col)*size,y+row*size,size,size,color);return art;
}
const centered=(text,y,size=2,color=P.ink)=>pixelText(text,Math.round((320-(text.length*6-1)*size)/2),y,size,color);
function slab(x,y,w,h,color=P.prop){return path(`M${x+6} ${y}h${w-12}v4h6v${h-8}h-6v4H${x+6}v-4h-6V${y+4}h6Z`,color);}
function card(text,y=154,color=P.blue,width){const w=width||Math.max(104,(text.length*6-1)*2+24);return slab((320-w)/2,y,w,30,color)+centered(text,y+8,2,P.black);}
function held(text,y=154,color=P.blue){const w=Math.max(104,(text.length*6-1)*2+24);return card(text,y,color,w)+slab((320-w)/2-10,y+13,24,16,P.ink)+slab((320+w)/2-14,y+13,24,16,P.ink);}
function pad(x,y,w=28,h=16,color=P.ink){return slab(x,y,w,h,color);}
function cube(x,y,size=24,color=P.blue){return rect(x,y,size,size,color)+rect(x+4,y+4,Math.max(4,size-12),4,P.ink)+rect(x+size-5,y+6,5,size-6,P.dim);}
function paper(x,y,w=42,h=34,color=P.blue,pattern=0){return rect(x,y,w,h,P.prop)+rect(x+3,y+3,w-6,h-6,P.black)+rect(x+7,y+7,10,7,color)+rect(x+22,y+8,w-28,4,P.dim)+rect(x+7,y+20,w-14,3,color)+rect(x+7,y+27,Math.max(6,w-22-pattern*3),3,P.dim);}
function board(y=164,pressed=-1,color=P.prop){let art=slab(83,y,154,24,P.dim)+rect(88,y+4,144,16,P.black);for(let row=0;row<2;row++)for(let col=0;col<12;col++)art+=rect(91+col*12,y+5+row*8,8,5,(pressed%24===row*12+col)?P.ink:color);return art;}
function burst(x,y,stage=0,color=P.prop,count=6){let art='';for(let i=0;i<count;i++){const dx=[-1,1,-.55,.55,-1,1,0,0][i%8],dy=[-.6,-.6,-1,-1,0,0,-1,1][i%8],s=stage===0?8:stage===1?6:4;art+=rect(Math.round(x+dx*(14+stage*14)),Math.round(y+dy*(10+stage*10)+stage*3),s,s,i%3===0?P.ink:color);}return art;}
function glass(x,y,color=P.blue){return at(x,y,path('M8 0h32v8h8v32h-8v8H8v-8H0V8h8Zm4 8v4H8v24h4v4h24v-4h4V12h-4V8Z',color)+rect(38,38,10,10,color)+rect(46,46,12,12,P.prop));}
function robot(x,y,pose=0,color=P.blue,cargo=false){return at(x,y,rect(12,-6,6,7,P.dim)+slab(0,0,32,25,color)+rect(5,5,22,12,P.black)+rect(8,8,5,5,P.ink)+rect(20,8,5,5,P.ink)+rect(5,25,22,9,P.dim)+rect(pose%2?2:5,34,8,5,color)+rect(pose%2?22:19,34,8,5,color)+(pose===3?pad(29,-4,12,10):pad(-8,21,12,10))+(cargo?cube(26,20,16,P.amber):''));}
function rail(y=185){return rect(48,y,224,4,P.dim)+[64,104,144,184,224].map(x=>rect(x,y-4,8,4,P.prop)).join('');}
function arrow(x,y,color=P.blue){return at(x,y,rect(0,5,20,6,color)+rect(16,0,6,16,color)+rect(22,4,6,8,color));}

// Each step is the source of truth for BOTH a visible pose and its contact sound.
// Normalized authored key times become absolute seconds once, per performance.
function statePlan(asset){
 const p=acting[asset.mood],steps=[];
 const add=(u,pose,effect=null,gain=.7)=>steps.push({at:n(u*asset.seconds),pose,effect,gain});
 add(0,'home');
 switch(asset.action){
  case 'start-card':case 'ready-card':case 'continue-card':case 'compact-card':
   add(.09,'lift','paper');add(.19,'reveal','latch');add(.48,'hold');add(.58,'fold','fold');add(.70,'unfold','ratchet');add(.79,'type','key');add(.85,'release','release',.4);add(.92,'home');break;
  case 'step-route':
   add(.08,'pick','paper');add(.19,'step1','wood',.55);add(.31,'step2','wood',.55);add(.43,'step3','wood',.60);add(.57,'reconsider','slide',.45);add(.68,'reorder','paper',.55);add(.80,'route','latch',.48);add(.91,'gather','paper',.4);add(.96,'home');break;
  case 'spy-console':{
   const count={happy:18,excited:24,proud:14,curious:16,determined:22,grumpy:22,sad:12}[asset.mood];
   for(let i=0;i<count;i++){const u=.075+i*.79/count;add(u,'key-'+i,asset.mood==='grumpy'&&i%6===5?'bash':asset.mood==='sad'?'softKey':['key','keyB','keyC','space'][i%4],i%4===0?.76:.55);add(u+.026,'up-'+i,'release',.28);}add(.93,'home');break;}
  case 'socket-toolbox':
   add(.10,'open','latch');add(.23,'pick','metal',.45);add(.37,'plug','latch');add(.49,'crank1','ratchet');add(.59,'crank2','ratchet');add(.69,'crank3','ratchet');add(.81,'unplug','pop',.45);add(.93,'home','wood',.4);break;
  case 'outbound-search':
   add(.10,'lens1','slide',.4);add(.22,'lens2','latch',.28);add(.34,'lens3','slide',.38);add(.45,'send','swipe',.5);add(.56,'outbound');add(.66,'incoming','paper',.5);add(.78,'catch','paper',.65);add(.88,'stack','wood',.38);add(.96,'home');break;
  case 'evidence-desk':
   add(.08,'receive','paper');add(.23,'left','slide',.4);add(.39,'right','slide',.4);add(.55,'zoom','latch',.36);add(.70,'compare','paper',.48);add(.84,'group','wood',.4);add(.94,'home','paper',.32);break;
  case 'test-gate':
   for(let i=0;i<3;i++){add(.10+i*.25,'load-'+i,'wood',.40);add(.20+i*.25,'scan-'+i,'latch',.40);add(.29+i*.25,'exit-'+i,'slide',.32);}add(.94,'home');break;
  case 'helper-hatch':
   add(.10,'open','ratchet');add(.23,'peek','pop',.5);add(.36,'one','landing',.4);add(.50,'two','landing',.42);add(.64,'three','landing',.44);add(.76,'go','swipe',.42);add(.88,'close','latch',.42);add(.96,'home');break;
  case 'helper-drill':
   add(.08,'assemble','landing',.4);add(.21,'salute','cloth',.35);add(.38,'go','paper',.5);add(.49,'march1','wood',.44);add(.59,'march2','wood',.48);add(.69,'march3','wood',.44);add(.81,'away','swipe',.4);add(.95,'home');break;
  case 'helper-courier':
   add(.12,'arrive','slide',.45);add(.27,'park','landing',.42);add(.42,'handover','paper');add(.61,'report','fold',.42);add(.81,'leave','swipe',.4);add(.95,'home');break;
  case 'helper-report':
   add(.10,'arrive','wood',.42);add(.24,'lineup','landing',.4);add(.38,'salute','cloth',.35);add(.51,'report','paper',.62);add(.73,'dismiss','cloth',.32);add(.86,'leave','slide',.4);add(.95,'home');break;
  case 'hourglass-lean':
   add(.16,'grain1');add(.33,'grain2');add(.50,'grain3');add(.67,'low');add(.78,'flip','cloth',.22);add(.89,'settle','cushion',.25);add(.96,'home');break;
  case 'answer-tray':
   add(.10,'page','paper');add(.24,'unfold','fold',.52);add(.43,'offer','slide',.58);add(.62,'present');add(.86,'withdraw','paper',.32);add(.95,'home');break;
  case 'jam-recoil':
   add(.09,'try1','ratchet',.6);add(.20,'jam1','creak',.68);add(.31,'try2','ratchet',.6);add(.39,'jam2','creak',.72);add(.49,'break','snap',.78);add(.60,'scatter','keycap',.55);add(.72,'error','failedAttempt',.62);add(.92,'home');break;
  case 'brake-settle':
   add(.08,'moving1','ratchet',.48);add(.20,'moving2','ratchet',.46);add(.34,'brake','brake',.6);add(.44,'settle','wood',.42);add(.60,'stopped','cloth',.34);add(.87,'lower','slide',.3);add(.96,'home');break;
  case 'squash-hello':
   add(.10,'contact','cushion',.66);add(.19,'squash');add(.32,'rebound','rubber',.44);add(.48,'look');add(.70,'settle','cloth',.2);add(.94,'home');break;
  case 'cushion-shield':
   add(.09,'tap1','cushion',.5);add(.18,'tap2','cushion',.53);add(.28,'tap3','cushion',.56);add(.38,'duck','cloth',.45);add(.48,'shield','rubber',.48);add(.65,'easy','paper',.4);add(.84,'peek');add(.95,'home');break;
  case 'complete-card':
   add(.08,'poise','paper',.45);add(.20,'reveal','trophyB',.9);add(.32,'burst1');add(.47,'burst2');add(.63,'hold');add(.82,'lower','cloth',.25);add(.95,'home');break;
  case 'failed-card':
   add(.10,'brace','creak',.6);add(.23,'strain','creak',.7);add(.36,'break','snap',.63);add(.46,'fallen','landing',.5);add(.55,'failed','failedAttempt',.72);add(.77,'hold');add(.90,'lower','cloth',.28);add(.97,'home');break;
  default:throw new Error('Missing state choreography: '+asset.action);
 }
 add(1,'home');
 const policy=asset.state==='waiting'?'sparse':sustainedStates.includes(asset.state)?'loop':'entry';
 return {steps,policy,intervalSeconds:asset.state==='waiting'?45:0,profile:p};
}

function backgroundDetail(asset,pose){
 if(asset.action==='spy-console'){
  const step=Math.floor(Number(pose.split('-')[1]||0)/3);let s='';
  for(let col=0;col<4;col++)for(let row=0;row<4;row++)s+=pixelText((row+col+step)%2?'1':'0',[12,36,264,288][col],12+((row*34+step*8+col*12)%120),2,row===step%4?GREEN:DEEP);
  s+=pixelText('> '+['RUN()','X++','0101','RUN()'][Math.floor(step/4)%4],106,24,2,GREEN);return s;
 }
 return '';
}
function props(a,pose){
 const m=a.mood,A=a.action,hot=m==='grumpy',home=pose==='home';let s='';
 if(A.endsWith('-card')&&['start-card','ready-card','continue-card','compact-card'].includes(A)){
  const text={ 'start-card':'NEW TASK','ready-card':'READY','continue-card':'CONTINUE','compact-card':'COMPACTED'}[A];
  if(['lift','reveal','hold','fold'].includes(pose)){s+=held(text,pose==='lift'?166:pose==='fold'?176:150,P.amber);if(pose==='reveal')s+=burst(54,166,0,P.amber,4)+burst(262,166,0,P.amber,4);}
  else if(['unfold','type','release'].includes(pose)){s+=board(164,pose==='type'?7:-1)+pad(72,pose==='type'?155:147)+pad(220,pose==='type'?155:147);s+=centered(text,22,2,P.amber);}
  else s+=slab(115,160,90,24,P.dim)+rect(145,155,30,5,P.prop);return s;
 }
 if(A==='step-route'){
  if(home||pose==='pick'||pose==='gather')return paper(133,153,54,32,P.blue)+pad(185,pose==='pick'?144:166);
  const count=pose==='step1'?1:pose==='step2'?2:3;
  for(let i=0;i<count;i++){const x=62+i*76,y=158-i*8+(pose==='reconsider'&&i===1?-18:0);s+=slab(x,y,44,30,pose==='reorder'&&i===1?P.amber:P.blue)+pixelText(String(pose==='reorder'?(i===1?3:i===2?2:1):i+1),x+17,y+8,2,P.black);if(i<count-1)s+=arrow(x+48,y+6,P.dim);}
  s+=pad(57+(count-1)*76,pose==='reconsider'?122:176,30,12);return s;
 }
 if(A==='spy-console'){
  const down=pose.startsWith('key-'),i=Number(pose.split('-')[1]||0);s+=board(164,down?(i*7)%24:-1,GREEN)+pad(84+i%3*8,down?154:146,28,14)+pad(204-i%3*8,down?149:154,28,14);
  if(hot&&down&&i%6===5){s+=burst(95,155,1,P.prop,8)+burst(228,155,1,P.prop,6)+at(38,130,keycap(16,'X'))+at(270,145,keycap(16,'E'));}
  if(m==='sad')s+=Array.from({length:9},(_,k)=>rect(84+k*17,185-(k+i)%3*3,6,6,k%2?P.water:P.blue)).join('');return s;
 }
 if(A==='socket-toolbox'){
  s+=slab(84,164,110,24,P.blue)+rect(126,171,24,6,P.black);
  if(home)return s+rect(88,156,102,8,P.prop)+rect(123,150,30,6,P.dim);
  s+=rect(84,146,10,18,P.prop)+rect(84,142,106,8,P.blue)+rect(226,152,38,36,P.dim)+rect(234,160,22,17,P.black);
  const plugged=['plug','crank1','crank2','crank3'].includes(pose);s+=cube(plugged?232:196,plugged?158:pose==='pick'?126:144,20,P.amber)+rect(plugged?214:188,plugged?164:148,18,6,P.prop);
  if(pose.startsWith('crank')){const k=Number(pose.at(-1));s+=rect(269,136,6,35,P.prop)+pad(k%2?264:254,k%2?132:154,25,14);if(hot)s+=burst(251,158,k%2,P.prop,4);}else s+=pad(195,134);return s;
 }
 if(A==='outbound-search'){
  s+=slab(126,146,66,40,DEEP)+rect(132,161,54,5,GREEN)+rect(156,150,5,32,GREEN)+rect(142,154,5,24,GREEN)+rect(174,154,5,24,GREEN);
  if(['home','lens1','lens2','lens3'].includes(pose)){const x={home:94,lens1:112,lens2:156,lens3:185}[pose];s+=glass(x,128)+pad(x+40,171);}
  if(['send','outbound'].includes(pose)){s+=paper(pose==='send'?218:266,pose==='send'?130:98,34,28,P.blue)+arrow(pose==='send'?200:242,120,P.blue);}
  if(['incoming','catch','stack'].includes(pose)){const x={incoming:248,catch:196,stack:98}[pose];s+=paper(x,150,42,32,P.amber)+paper(x+10,146,42,32,P.blue)+pad(x-8,174);}
  return s;
 }
 if(A==='evidence-desk'){
  const left=pose==='left',right=pose==='right',zoom=pose==='zoom';
  if(home)return paper(132,150,52,36,P.blue);
  s+=paper(62,left?140:152,54,36,P.blue,1)+paper(202,right?140:152,54,36,P.amber,2);
  if(zoom||['compare','group'].includes(pose)){s+=slab(132,143,54,42,P.dim)+cube(140,151,16,P.blue)+cube(160,160,16,P.amber);if(pose==='group')s+=rect(122,181,74,5,P.blue);}
  else s+=glass(left?56:right?194:120,124);
  s+=pad(left?48:right?246:146,172,26,14);return s;
 }
 if(A==='test-gate'){
  s+=rail()+rect(148,144,8,40,P.prop)+rect(196,144,8,40,P.prop)+rect(148,136,56,12,P.dim)+rect(169,139,14,6,P.amber);
  const [phase,index]=pose.split('-'),i=Number(index||0),x=phase==='scan'?164:phase==='exit'?226:76;
  s+=cube(x,160,24,i%2?P.blue:P.prop);if(phase==='scan')s+=rect(158,153,34,4,P.amber)+rect(158,176,34,4,P.amber);else s+=cube(46,170,16,P.blue);
  s+=pad(phase==='load'?65:252,phase==='load'?150:158,24,14);return s;
 }
 if(A==='helper-hatch'){
  s+=rect(66,181,190,6,P.dim);
  if(home||pose==='close')return s+slab(119,157,82,24,P.blue);
  s+=rect(116,159,12,22,P.blue)+rect(194,159,12,22,P.blue)+rect(120,152,78,8,P.prop);
  if(pose==='open')return s+burst(160,165,0,P.prop,4);
  const count={peek:1,one:1,two:2,three:3,go:3}[pose]||1;
  for(let i=0;i<count;i++)s+=robot(pose==='go'?202+i*38:pose==='peek'?144:64+i*78,pose==='peek'?164:141,i%2,P.blue,true);
  if(pose==='go')s+=centered('GO!',24,2,P.amber)+pad(240,116,36,16);return s;
 }
 if(A==='helper-drill'){
  if(home)return rect(86,182,148,5,P.dim)+rect(94,173,20,9,P.blue)+rect(154,173,20,9,P.blue)+rect(214,173,20,9,P.blue);
  const k=pose.startsWith('march')?Number(pose.at(-1)):pose==='away'?4:0;
  for(let i=0;i<3;i++)s+=robot(57+i*67+k*28,144-(k%2)*6,pose==='salute'?3:k%2,i===0?P.amber:P.blue,true);
  if(['salute','go'].includes(pose))s+=pad(258,57,28,20);
  if(['go','march1','march2','march3','away'].includes(pose))s+=centered('GO!',22,3,P.amber);return s;
 }
 if(A==='helper-courier'){
  if(home)return slab(116,180,88,7,P.dim);
  const x={arrive:24,park:72,handover:86,report:86,leave:260}[pose];s+=robot(x,143,pose==='arrive'?1:0,P.blue,pose!=='report');
  if(['handover','report'].includes(pose))s+=held('REPORT',154,P.blue);else s+=paper(x+34,152,40,28,P.amber);return s;
 }
 if(A==='helper-report'){
  if(home)return slab(100,181,120,7,P.dim);
  const dx=pose==='arrive'?-55:pose==='leave'?150:0;
  for(let i=0;i<3;i++)s+=robot(66+i*72+dx,pose==='arrive'?146-i%2*4:144,pose==='salute'?3:i%2,i===1?P.amber:P.blue);
  if(['salute','report','dismiss'].includes(pose))s+=centered('REPORT!',23,2,P.blue);
  if(pose==='report')s+=held('REPORT',152,P.blue);
  if(pose==='salute')s+=pad(260,55,28,18);return s;
 }
 if(A==='hourglass-lean'){
  const x=129,y=141; s+=rect(x-4,y,70,7,P.prop)+rect(x-4,y+40,70,7,P.prop)+path(`M${x} ${y+7}h8v8h8v8h-8v10h-8Zm54 0h8v26h-8V${y+23}h-8v-8h8Z`,P.dim);
  if(pose==='flip')s+=rect(124,162,70,7,P.amber)+pad(194,154,24,16);
  else{const amount={home:4,grain1:3,grain2:2,grain3:1,low:0,settle:4}[pose]??4;for(let j=0;j<amount;j++)s+=rect(142+j*3,152+j*4,30-j*6,4,P.amber);for(let j=0;j<4-amount;j++)s+=rect(139+j*3,178-j*4,36-j*6,4,P.amber);s+=rect(155,164+(amount%3)*3,5,5,P.amber)+pad(203,166,30,16);}
  return s;
 }
 if(A==='answer-tray'){
  s+=slab(81,180,158,7,P.dim);
  if(home)return s+paper(137,151,46,29,P.blue);
  if(['page','unfold','withdraw'].includes(pose))return s+paper(pose==='page'?144:122,pose==='page'?143:150,pose==='page'?36:76,32,P.blue)+pad(197,169);
  return s+held('ANSWER',pose==='offer'?149:154,P.blue)+arrow(263,159,P.blue);
 }
 if(A==='jam-recoil'){
  s+=rect(82,179,158,8,P.dim);
  if(['break','scatter','error'].includes(pose)){s+=cube(pose==='break'?104:75,pose==='break'?149:163,24,P.prop)+cube(pose==='break'?183:216,pose==='break'?148:160,24,P.blue);if(pose!=='error')s+=burst(164,164,pose==='break'?0:2,P.prop,8);else s+=centered('ERROR',23,3,P.red);}
  else{s+=slab(114,151,91,30,P.prop)+rect(133,159,42,12,P.black)+rect(151,143,10,34,P.blue);s+=pad(pose==='try1'||pose==='try2'?194:202,pose.startsWith('jam')?153:140);if(pose.startsWith('jam'))s+=burst(166,159,0,P.red,4);}
  return s;
 }
 if(A==='brake-settle'){
  s+=rail()+rect(259,145,7,37,P.prop)+pad(pose==='brake'||pose==='settle'?242:254,pose==='brake'||pose==='settle'?163:140,26,16,P.red);
  const delta={home:0,moving1:16,moving2:40,brake:48,settle:52,stopped:52,lower:12}[pose]||0;
  for(let i=0;i<3;i++)s+=cube(55+i*47+delta,164,20,i%2?P.prop:P.blue);
  if(['stopped','settle'].includes(pose))s+=centered('STOPPED',22,2,P.blue);return s;
 }
 if(A==='squash-hello'){
  const x={happy:45,excited:253,proud:258,curious:40,determined:145,grumpy:264,sad:62}[m],y=m==='determined'?153:135;
  if(['contact','squash'].includes(pose))s+=pad(x,y,40,22,P.blue)+burst(x+18,y+8,pose==='contact'?0:1,P.blue,4);
  if(pose==='rebound')s+=burst(x+18,y+8,2,m==='grumpy'?P.red:P.blue,4);
  if(pose==='look'&&m==='happy')s+=star(34,31,24,P.amber);
  if(pose==='look'&&m==='curious')s+=glass(247,134);
  if(pose==='look'&&m==='grumpy')s+=pad(258,145,32,16,P.prop);
  return s;
 }
 if(A==='cushion-shield'){
  if(pose.startsWith('tap')){const k=Number(pose.at(-1)),[x,y]=[[36,30],[249,91],[46,143]][k-1];return pad(x,y,38,24,P.blue)+burst(x+17,y+8,k%2,P.blue,4);}
  if(['shield','easy','peek'].includes(pose)){const y=pose==='peek'?148:116;s+=slab(79,y,162,70,m==='sad'?P.lightWater:hot?P.prop:P.blue)+rect(90,y+8,140,5,m==='sad'?P.blue:P.ink)+centered('EASY!',y+25,3,P.black)+pad(66,y+39,27,20)+pad(224,y+39,27,20);}
  return s;
 }
 if(A==='complete-card'){
  if(home||pose==='poise'||pose==='lower')return held('COMPLETE',pose==='poise'?164:154,P.amber);
  s+=held('COMPLETE',154,P.ink);
  const ctx={motion:false,ink:P.dark};s+=trophy(ctx);
  if(['reveal','burst1','burst2'].includes(pose)){const k={reveal:0,burst1:1,burst2:2}[pose];s+=burst(30,40,k,P.red,8)+burst(286,44,k,P.blue,8)+burst(30,160,k,P.ink,8)+burst(290,158,k,P.dark,8);}
  return s;
 }
 if(A==='failed-card'){
  if(['failed','hold','lower','home'].includes(pose))return held('FAILED',154,P.red)+(pose==='home'?'':cube(43,163,20,P.dim)+cube(260,169,16,P.dim));
  if(['brace','strain'].includes(pose))return rect(95,150,132,24,P.dim)+cube(126,121,24,P.prop)+cube(170,121,24,P.blue)+pad(82,174)+pad(218,174)+(pose==='strain'?path('M156 149h8v8h-8v9h8v8h-8Z',P.black):'');
  return cube(pose==='break'?89:57,pose==='break'?155:168,24,P.prop)+cube(pose==='break'?214:251,pose==='break'?149:165,20,P.dim)+burst(159,158,pose==='break'?0:2,P.dim,6);
 }
 throw new Error('Undrawn action '+A);
}

function poseOffset(asset,pose){
 const p=acting[asset.mood],m=asset.mood;
 if(pose==='home')return [0,0];
 if(['contact','squash','jam1','jam2','break','brake'].includes(pose))return [m==='grumpy'?-4:2,4];
 if(['reveal','go','rebound','one','two','three'].includes(pose))return [0,-p.lift];
 if(['duck','shield','easy'].includes(pose))return [0,10];
 if(pose==='left'||pose==='lens1')return [-5,0];
 if(pose==='right'||pose==='lens3')return [5,0];
 if(pose.startsWith('key-'))return [(Number(pose.split('-')[1])%2?1:-1)*(m==='grumpy'?3:1),m==='excited'?3:m==='sad'?2:1];
 if(m==='sad')return [0,3];
 if(m==='proud')return [2,-2];
 return [0,0];
}
function timedFrames(asset,plan,draw,merge=false){
 const {steps}=plan;
 const drawings=steps.slice(0,-1).map((step,i)=>({step,i,art:draw(step.pose)}));
 const groups=merge?[...new Set(drawings.map(d=>d.art))].map(art=>drawings.filter(d=>d.art===art)):drawings.map(d=>[d]);
 return groups.map(items=>{
  const {step,i,art}=items[0],indexes=items.map(d=>d.i);
  const times=[0,...steps.slice(1).map(e=>e.at/asset.seconds)];
  const values=steps.map((_,j)=>Number(indexes.includes(j)||j===steps.length-1&&indexes.includes(0)));
  return group(`<animate attributeName="opacity" values="${values.join(';')}" keyTimes="${times.map(n).join(';')}" dur="${asset.seconds}s" calcMode="discrete" repeatCount="indefinite"/>`+art,`opacity="${indexes.includes(0)?1:0}" data-pose="${step.pose}" data-step="${i}"`);
 }).join('');
}
function faceArt(asset,plan,motion){
 const success=asset.outcome==='success',p=plan.profile;
 const ctx={mood:asset.mood,state:'working',quiet:false,complete:false,motion,ink:success?P.dark:P.ink,bg:success?P.gold:P.black,cheek:success?'#D8576C':P.cheek,actorMotion:''};
 if(asset.outcome==='failure'){
  // Outcome must stay readable even with an excited mood: keep the eyes, restrain
  // the laughing mouth. This is a situational pose, not a silent mood change.
  ctx.mouthOverride=rect(148,134,24,6,P.ink);ctx.suppressDecor=true;
 }
 if(asset.mood==='sad'&&['waiting','poked','tap_spam','task_complete'].includes(asset.state))ctx.state='listening';
 const offsets=plan.steps.map(e=>poseOffset(asset,e.pose).join(' '));
 const anim=motion?`<animateTransform attributeName="transform" type="translate" values="${offsets.join(';')}" keyTimes="${plan.steps.map(e=>n(e.at/asset.seconds)).join(';')}" dur="${asset.seconds}s" calcMode="discrete" repeatCount="indefinite"/>`:'';
 const raw=face(ctx);
 return at(0,-12,group(anim+(motion?closeTimelines(raw,asset.seconds):raw),'data-part="state-face"'));
}
function renderStateScene(asset){
 const plan=statePlan(asset),id='boop-v3-'+asset.id.replaceAll('.','-'),success=asset.outcome==='success';
 const ctx={motion:true,ink:P.dark};
 let back=success?closeTimelines(victoryBackground(ctx),asset.seconds):'';
 const intro=faceArt(asset,plan,true),art=back+timedFrames(asset,plan,p=>backgroundDetail(asset,p),true)+intro+group(timedFrames(asset,plan,p=>props(asset,p)),'data-part="state-action"');
 const stillPose=asset.action==='complete-card'?'hold':asset.action==='failed-card'?'failed':asset.state==='error'?'error':asset.state==='stopped'?'stopped':asset.state==='tap_spam'?'easy':asset.state==='reply_ready'?'present':asset.action==='helper-drill'?'go':asset.action==='helper-report'?'report':asset.state==='starting'?'reveal':'home';
 let finalArt=art;
 if(success)finalArt=finalArt.replace(/<(rect|path)([^>]* fill="#FFD54A"[^>]*)\/>/g,(_,tag,attrs)=>`<${tag}${attrs}><animate attributeName="fill" values="#FFD54A;#FFC94A;#FFB84A;#FFC94A;#FFD54A" keyTimes="0;0.25;0.5;0.75;1" dur="${asset.seconds}s" repeatCount="indefinite" calcMode="linear"/></${tag}>`);
 const still=(success?rect(0,0,320,192,P.gold):'')+backgroundDetail(asset,'home')+faceArt(asset,plan,false)+props(asset,stillPose);
 return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="${id}" data-mood="${asset.mood}" data-state="${asset.state}" data-action="${asset.action}" data-loop-seconds="${asset.seconds}" role="img" aria-labelledby="${id}-title ${id}-desc" shape-rendering="crispEdges" overflow="hidden"><title id="${id}-title">${safe(asset.mood+' · '+asset.name)}</title><desc id="${id}-desc">${safe(asset.caption)} Shared SVG and sound cue clock. Bottom 48 pixels reserved for host text.</desc><style>#${id} .state-still{display:none}@media(prefers-reduced-motion:reduce){#${id}:not([data-motion="on"]) .state-motion{display:none}#${id}:not([data-motion="on"]) .state-still{display:inline}}</style><defs><clipPath id="${id}-art"><rect width="320" height="192"/></clipPath></defs><rect width="320" height="240" fill="#000000"/><g clip-path="url(#${id}-art)"><g class="state-motion">${finalArt}</g><g class="state-still">${still}</g></g><g id="reserved-text-zone" data-part="reserved-text-zone"/></svg>`;
}
function stateScore(asset){
 const plan=statePlan(asset),events=plan.steps.flatMap((s,i)=>s.effect?[{at:s.at,effect:s.effect,gain:n(s.gain*plan.profile.gain),pitch:['trophyB','failedAttempt'].includes(s.effect)?1:plan.profile.pitch,label:s.pose.replaceAll('-',' '),sync:{part:'state-action',pose:s.pose,step:i}}]:[]);
 for(const e of events)if(!effects[e.effect])throw new Error('Missing effect '+e.effect);
 const tailSeconds=n(Math.max(0,...events.map(e=>e.at+effects[e.effect].duration-asset.seconds)));
 return {id:asset.id,seconds:asset.seconds,policy:plan.policy,intervalSeconds:plan.intervalSeconds,description:'Material-specific procedural contacts; no background music or voice. '+asset.caption,character:plan.profile.character,tailSeconds,events};
}

return {pixelText,statePlan,renderStateScene,stateScore};},
"state-catalog.mjs":()=>{
const {moods}=load("visual/base.mjs");
const stateOrder=['no_app','asleep','idle','listening','starting','planning','working','terminal','tool_use','searching','analyzing','testing','delegating','helper_return','waiting','needs_you','reply_ready','task_complete','error','stopped','poked','tap_spam'];
const sustainedStates=['working','idle','asleep','no_app','planning','terminal','tool_use','searching','analyzing','testing','waiting'];
// Seven named characters, not a new intensity axis. Timing is authored per mood.
const acting={
  happy:{pace:1,gain:.70,pitch:1.04,lift:4,character:'Bouncy, open-hearted and a little distractible.'},
  excited:{pace:.78,gain:.72,pitch:1.08,lift:8,character:'XD delight; rushes, overshoots and catches up.'},
  proud:{pace:1.12,gain:.65,pitch:.96,lift:3,character:'Smirking show-off; poised reveals and deliberate holds.'},
  curious:{pace:1.08,gain:.60,pitch:1.03,lift:3,character:'Alternating big/small eyes; peers, compares and probes.'},
  determined:{pace:.92,gain:.70,pitch:1,lift:2,character:'Upward brows; steady, square and methodical.'},
  grumpy:{pace:.76,gain:.84,pitch:.94,lift:5,character:'Anger mark; compressed windups, sharp impacts, flying square fragments.'},
  sad:{pace:1.28,gain:.48,pitch:.98,lift:2,character:'Hesitant but still doing the job; blue cube tears and soft landings.'}
};
const definitions=[
 ['starting',1,'start-card','New task, coming through','Flip NEW TASK, then unfold the keyboard.',3.8,{startContext:'new_task'}],
 ['starting',2,'ready-card','Ready at the desk','READY is a connection greeting, not a new task.',3.8,{startContext:'session'}],
 ['starting',3,'continue-card','Back to it','CONTINUE; reopen the workstation.',3.8,{startContext:'continuation'}],
 ['starting',4,'compact-card','Squeezed and back','COMPACTED is the context made smaller; the work goes on.',3.8,{startContext:'compacted'}],
 ['planning',1,'step-route','A plan in three blocks','Lay out numbered steps, reconsider the middle card, then restore the stack.',4.8],
 ['terminal',1,'spy-console','Tiny terminal operator','Rhythmic mechanical typing, green toy code and chunky binary rain.',3.8],
 ['tool_use',1,'socket-toolbox','The right tool for the job','Unlatch the toolbox, seat a plug and work the chunky lever.',4.4],
 ['searching',1,'outbound-search','Out into the world','Sweep a big magnifier over a globe; send a query tile, receive material.',4.8],
 ['analyzing',1,'evidence-desk','Let me look at that','Compare incoming cards, magnify their patterns and group the clues.',4.8],
 ['testing',1,'test-gate','Through the test gate','Feed three blocks through an amber inspection gate; no invented pass result.',4.4],
 ['delegating',1,'helper-hatch','Little helpers, launch','Open a hatch and dispatch three tiny robots with work cubes.',4.4],
 ['delegating',2,'helper-drill','Squad, move out','Salute with one soft pad; GO! card and a toy-robot formation.',4.8],
 ['helper_return',1,'helper-courier','Delivery from a helper','A courier slides in with a REPORT card; Boop catches the delivery.',4.2],
 ['helper_return',2,'helper-report','Reporting for duty','Returning helpers line up, salute, hand over REPORT and stand down.',4.8],
 ['waiting',1,'hourglass-lean','Still waiting on the machine','Lean beside a broad hourglass; grains fall, then a slow flip.',6.2],
 ['reply_ready',1,'answer-tray','An answer for you','Unfold a page and push an ANSWER tray forward; no celebration.',4.2],
 ['error',1,'jam-recoil','That did not work','Try a stuck mechanism twice; it spits out block fragments. ERROR, not task over.',3.8],
 ['stopped',1,'brake-settle','Putting the tools down','Brake a conveyor; the loose blocks settle beneath STOPPED.',4.2],
 ['poked',1,'squash-hello','Oh, hello there','A broad screen contact, a squash and a mood-shaped rebound.',2.8],
 ['tap_spam',1,'cushion-shield','Easy, easy!','Contacts arrive from several sides; Boop ducks behind a soft EASY! shield.',3.8],
 ['task_complete',4,'complete-card','Complete, with ceremony','Hold COMPLETE under a trophy, square fireworks and a full victory accent.',5.8,{outcome:'success'}],
 ['task_complete',5,'failed-card','The task fell apart','Brace a failing work block; it separates. Hold FAILED, then settle. No victory.',5.2,{outcome:'failure'}]
];
const additions=definitions.flatMap(([state,variation,action,name,caption,baseSeconds,extra={}])=>moods.map(mood=>({
  id:`${mood}.${state}.${String(variation).padStart(2,'0')}`,mood,state,variation,action,name,caption,
  seconds:Number((baseSeconds*(state==='task_complete'?1:acting[mood].pace)).toFixed(3)),
  renderer:'state-v3',approval:'Review candidate',...extra
})));

return {stateOrder,sustainedStates,acting,additions};},
"timing.mjs":()=>{
// Inspect our generated SVG timelines, not historical captions or guessed tempos.
function tracksFromSVG(svg){
  const stack=[],tracks=[];
  for(const match of svg.matchAll(/<(\/?)([\w:-]+)\b([^>]*?)(\/?)>/g)){
    const [,closing,tag,tail,self]=match;
    if(closing){stack.pop();continue;}
    const attrs=Object.fromEntries([...tail.matchAll(/([\w:-]+)="([^"]*)"/g)].map(m=>[m[1],m[2]]));
    if((tag==='animate'||tag==='animateTransform')&&attrs.keyTimes){
      const parent=stack.at(-1),part=[...stack].reverse().find(x=>x.attrs['data-part'])?.attrs['data-part'];
      tracks.push({part,parent:parent?.attrs||{},attribute:attrs.attributeName,type:attrs.type,values:attrs.values.split(';'),times:attrs.keyTimes.split(';').map(t=>Number(t)*parseFloat(attrs.dur)),sync:attrs['data-audio-sync']});
    }
    if(!self)stack.push({tag,attrs});
  }
  return tracks;
}
function entrances(tracks,part){
  const events=[];
  for(const track of tracks.filter(t=>t.part===part&&t.attribute==='opacity')){
    const frame=track.parent['data-frame'],pose=track.parent['data-pose'];
    if(frame===undefined&&pose===undefined)continue;
    for(let i=1;i<track.values.length;i++)if(Number(track.values[i])===1&&Number(track.values[i-1])===0)
      events.push({at:Number(track.times[i].toFixed(6)),frame:frame===undefined?null:Number(frame),pose:pose||null,part});
  }
  return events.sort((a,b)=>a.at-b.at);
}

return {tracksFromSVG,entrances};},
"visual/base.mjs":()=>{
// Boop V4: big-eyed minimal faces and a square-particle effects language.
// Pixel geometry + discrete SMIL animation. No runtime dependencies or audio.
const moods = ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad"];
const states = ["idle", "working", "needs_you", "task_complete", "listening", "asleep", "no_app"];
const palette = { ink: "#F8F7EF", black: "#000000", cheek: "#F1787D", blue: "#71B7F5", water: "#3597E4", lightWater: "#BEE9FF", amber: "#F4BC50", red: "#FF596C", dim: "#757568", prop: "#B6B6A5", gold: "#FFD54A", dark: "#302338", ochre: "#EDAE26" };
const label = text => text.replaceAll("_", " ").replace(/\b\w/g, c => c.toUpperCase());
const esc = text => String(text).replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;");
const rect = (x, y, w, h, fill = palette.ink) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}"/>`;
const path = (d, fill = palette.ink) => `<path d="${d}" fill="${fill}"/>`;
const block = (x, y, w, h, fill = palette.ink) => path(`M${x+1} ${y}h${w-2}v1h1v${h-2}h-1v1H${x+1}v-1h-1V${y+1}h1Z`, fill);
const group = (art, attrs = "") => `<g${attrs ? " " + attrs : ""}>${art}</g>`;
const at = (x, y, art) => group(art, `transform="translate(${x} ${y})"`);
function animate(ctx, attribute, values, seconds, times, repeat = "indefinite", begin = 0) {
  if (!ctx.motion) return "";
  return `<animate attributeName="${attribute}" values="${values}" keyTimes="${times}" dur="${seconds}s" begin="${begin}s" repeatCount="${repeat}" calcMode="discrete" fill="freeze"/>`;
}
function move(ctx, values, seconds, times, repeat = "indefinite", begin = 0) {
  if (!ctx.motion) return "";
  return `<animateTransform attributeName="transform" type="translate" values="${values}" keyTimes="${times}" dur="${seconds}s" begin="${begin}s" repeatCount="${repeat}" calcMode="discrete" fill="freeze"/>`;
}
const opacity = (ctx, values, seconds, times, repeat = "indefinite", begin = 0) => animate(ctx, "opacity", values, seconds, times, repeat, begin);
function frames(ctx, drawings, seconds, part) {
  const times = Array.from({length:drawings.length+1}, (_, i) => i/drawings.length).join(";");
  return group(drawings.map((drawing, i) => {
    const values = Array.from({length:drawings.length+1}, (_, k) => Number(k % drawings.length === i)).join(";");
    return group(opacity(ctx, values, seconds, times) + drawing, `opacity="${i===0?1:0}" data-frame="${i}"`);
  }).join(""), `data-part="${part}"`);
}
function fourEye(x, y, w, h, fill) {
  const a=(w-4)/2, b=(h-4)/2;
  return block(x,y,a,b,fill)+block(x+a+4,y,a,b,fill)+block(x,y+b+4,a,b,fill)+block(x+a+4,y+b+4,a,b,fill);
}
function star(x,y,size,color) {
  const s=size/8;
  return at(x,y,path(`M${3*s} 0h${2*s}v${2*s}h${s}v${s}h${2*s}v${2*s}h-${2*s}v${s}h-${s}v${2*s}h-${2*s}v-${2*s}h-${s}v-${s}H0V${3*s}h${2*s}v-${s}h${s}Z`,color));
}
function slopedLid(x,y,right,ctx,strength=4) {
  return Array.from({length:5},(_,i)=>rect(x+i*8,y,8,2+(right?4-i:i)*strength,ctx.bg)).join("");
}
function sadLid(x,y,right,ctx) {
  return Array.from({length:5},(_,i)=>rect(x+i*8,y,8,3+(right?i:4-i)*4,ctx.bg)).join("");
}
function eyePose(ctx) {
  const {mood,state,ink}=ctx;
  if(state==="asleep")return block(68,94,40,5,ink)+block(212,94,40,5,ink);
  if(state==="no_app")return block(68,94,40,8,ink)+block(212,94,40,8,ink);
  if(mood==="happy")return group(fourEye(62,56,52,56,ink)+fourEye(206,56,52,56,ink)+star(77,69,24,ctx.bg)+star(221,69,24,ctx.bg),'data-part="happy-eyes"');
  if(mood==="excited") {
    const steps=[0,6,12,18,12,6,0];
    return group(steps.map((x,i)=>rect(71+x,70+i*6,12,6,ink)+rect(237-x,70+i*6,12,6,ink)).join(""),'data-part="scrunched-eyes"');
  }
  if(mood==="proud")return fourEye(65,75,46,34,ink)+fourEye(211,70,42,40,ink)+rect(65,75,46,13,ctx.bg)+rect(211,70,42,6,ctx.bg)+rect(63,69,30,4,ink)+rect(221,61,30,4,ink);
  if(mood==="curious") {
    const poses=[
      fourEye(74,82,28,28,ink)+fourEye(201,53,62,62,ink),
      fourEye(67,69,42,42,ink)+fourEye(211,69,42,42,ink),
      fourEye(57,53,62,62,ink)+fourEye(218,82,28,28,ink),
      fourEye(67,66,42,46,ink)+fourEye(211,70,42,42,ink)
    ];
    return frames(ctx,poses,state==="idle"?3.6:2.8,"curious-eyes");
  }
  if(mood==="determined")return fourEye(67,80,42,30,ink)+fourEye(211,80,42,30,ink)+group(
    rect(65,68,15,4,ink)+rect(80,70,15,4,ink)+rect(95,72,14,4,ink)+
    rect(211,72,14,4,ink)+rect(225,70,15,4,ink)+rect(240,68,15,4,ink),'data-part="gentle-brows"');
  if(mood==="grumpy")return fourEye(68,70,40,44,ink)+fourEye(212,70,40,44,ink)+slopedLid(68,70,false,ctx)+slopedLid(212,70,true,ctx);
  return fourEye(68,66,40,48,ink)+fourEye(212,66,40,48,ink)+sadLid(68,66,false,ctx)+sadLid(212,66,true,ctx);
}
function eyes(ctx) {
  if(ctx.eyeOverride)return ctx.eyeOverride;
  if(["asleep","no_app"].includes(ctx.state))return eyePose(ctx);
  const period=ctx.state==="listening"?8.4:7.2;
  const open=group(opacity(ctx,"1;0;1;1",period,"0;0.78;0.805;1")+eyePose(ctx));
  const closed=group(opacity(ctx,"0;1;0;0",period,"0;0.78;0.805;1")+block(68,99,40,5,ctx.ink)+block(212,99,40,5,ctx.ink),"opacity=\"0\"");
  return group(open+closed,"data-part=\"eyes\"");
}
function mouth(ctx) {
  if(ctx.mouthOverride)return ctx.mouthOverride;
  const {mood,state,ink,bg}=ctx;
  if(["asleep","no_app"].includes(state))return block(148,132,24,4,ink);
  if(state==="listening") {
    if(mood==="happy")return path("M150 129h4v4h12v-4h4v8h-20Z",ink);
    if(mood==="sad")return path("M147 137h6v-5h14v5h6v5h-10v-5h-6v5h-10Z",ink);
  }
  if(mood==="happy")return path("M150 129h4v4h12v-4h4v8h-20Z",ink);
  if(mood==="excited")return group(
    path("M138 125h44v18h-6v7h-6v5h-20v-5h-6v-7h-6Z",ink)+
    path("M144 131h32v10h-6v8h-20v-8h-6Z",bg)+rect(150,144,20,5,ctx.cheek),'data-part="wide-laugh"');
  if(mood==="proud")return path("M137 132h30v-5h8v-5h8v11h-7v5h-7v5h-32Z",ink)+rect(140,132,23,3,bg);
  if(mood==="curious")return path("M152 129h16v16h-16Zm4 4v8h8v-8Z",ink);
  if(mood==="determined")return block(143,131,34,8,ink)+rect(152,134,3,5,bg)+rect(164,134,3,5,bg);
  if(mood==="grumpy") {
    if(state==="task_complete")return path("M140 134h24v-5h12v5h-7v6h-29Z",ink);
    return path("M141 135h6v-6h26v6h6v12h-38Z",ink)+rect(146,140,28,7,bg)+rect(152,130,3,6,bg)+rect(165,130,3,6,bg);
  }
  if(state==="task_complete")return path("M141 128h6v5h26v-5h6v13h-6v5h-26v-5h-6Z",ink)+rect(148,140,24,4,ctx.cheek);
  return path("M141 134h6v-7h26v7h6v18h-9v-6h-20v6h-9Z",ink)+rect(150,140,20,6,ctx.cheek);
}
function cheeks(ctx) {
  const y=ctx.mood==="excited"?120:124;
  return block(51,y,14,9,ctx.cheek)+block(69,y,14,9,ctx.cheek)+block(237,y,14,9,ctx.cheek)+block(255,y,14,9,ctx.cheek);
}
function anger(ctx) {
  const mark=path("M0 6h6V0h5v11H0ZM17 0h5v6h6v5H17ZM0 17h11v11H6v-6H0ZM17 17h11v5h-6v6h-5Z",palette.red);
  return at(270,41,group(move(ctx,"0 0;0 -2;1 -2;0 0;0 0",2.4,"0;0.25;0.4;0.55;1")+mark,"data-part=\"anger-mark\""));
}
// Particles are independent squares. Their stepped trajectories imply acceleration,
// impact and rebound; there are no solid tear ribbons or scaled/blurred sprites.
function splash(ctx,x,y,phase=0) {
  let art="";
  for(const [i,dx]of[-17,-9,10,19].entries()) {
    const size=i%2?4:3, color=i%2?palette.lightWater:palette.blue;
    if(!ctx.motion){art+=rect(dx, i%2?-5:2,size,size,color);continue;}
    art+=group(move(ctx,`0 0;${Math.round(dx*.3)} -4;${Math.round(dx*.65)} -8;${dx} -4;${dx+Math.sign(dx)*4} 6;0 0`,1.2,"0;0.2;0.4;0.6;0.85;1","indefinite",phase)+
      opacity(ctx,"0;1;1;1;0;0",1.2,"0;0.2;0.4;0.6;0.85;1","indefinite",phase)+rect(0,0,size,size,color),'opacity="0"');
  }
  return at(x,y,group(art,'data-part="square-splash"'));
}
function tears(ctx) {
  let art="";
  if(ctx.state==="working") {
    // Four staggered lanes per eye: a broad waterfall of separate little cubes.
    for(const [side,x]of[69,223].entries()) {
      for(let lane=0;lane<4;lane++)for(let j=0;j<7;j++) {
        const size=[5,4,6,4,5,4,6][(j+lane)%7];
        const color=[palette.blue,palette.lightWater,palette.water][(j+lane+side)%3];
        const phase=-j*(1.4/7)-lane*.045-side*.09;
        art+=at(x+lane*7,ctx.motion?109:109+j*9,group(
          move(ctx,"0 0;0 5;1 13;0 25;-1 40;1 59;0 0",1.4,"0;0.17;0.34;0.51;0.68;0.88;1","indefinite",phase)+
          opacity(ctx,"1;1;1;1;1;0;1",1.4,"0;0.17;0.34;0.51;0.68;0.88;1","indefinite",phase)+rect(0,0,size,size,color),`data-part="tear-particle" data-lane="${lane}"`));
      }
      art+=splash(ctx,x+4,176,-side*.6)+splash(ctx,x+20,177,-.3-side*.6);
    }
    return group(art,'data-part="square-tears" data-width="28"');
  }
  for(const [side,x]of[78,232].entries()) {
    for(let j=0;j<5;j++) {
      const size=[7,4,6,5,4][j],color=[palette.blue,palette.lightWater,palette.water][j%3];
      const dx=[0,5,-2,4,1][j];
      const stillY=112+j*12;
      art+=at(x+dx,ctx.motion?112:stillY,group(
        move(ctx,"0 0;0 4;1 11;-1 23;2 40;1 58;0 0",1.5,"0;0.17;0.34;0.51;0.68;0.88;1","indefinite",-j*.3-side*.15)+
        opacity(ctx,"1;1;1;1;1;0;1",1.5,"0;0.17;0.34;0.51;0.68;0.88;1","indefinite",-j*.3-side*.15)+rect(0,0,size,size,color),'data-part="tear-particle"'));
    }
    art+=splash(ctx,x+3,174,-side*.6);
  }
  return group(art,'data-part="square-tears"');
}
function faceMotion(ctx) {
  if(ctx.actorMotion!==undefined)return ctx.actorMotion;
  const {mood,state}=ctx;
  if(["asleep","no_app"].includes(state))return move(ctx,"0 0;0 -1;0 -2;0 -1;0 0",8,"0;0.2;0.4;0.6;1");
  if(state==="needs_you")return move(ctx,"0 0;-3 -3;2 1;-2 -2;0 0;0 0",2.2,"0;0.15;0.3;0.45;0.65;1","1");
  if(state==="task_complete") {
    const poses={happy:"0 0;-4 -4;4 -4;0 0;0 0",excited:"0 0;0 -10;0 2;0 -6;0 0",proud:"0 0;0 8;0 10;0 2;0 0",curious:"0 0;-4 -3;4 -3;0 0;0 0",determined:"0 0;0 -4;0 3;0 1;0 0",grumpy:"0 0;0 3;-2 0;0 0;0 0",sad:"0 0;0 3;-1 1;1 1;0 0"};
    return move(ctx,poses[mood],3.4,"0;0.2;0.45;0.7;1","1");
  }
  if(state==="listening")return move(ctx,"0 0;0 0;0 -2;0 0;0 0",6,"0;0.25;0.4;0.65;1");
  if(state==="idle") {
    if(mood==="curious")return move(ctx,"-3 1;0 -2;3 1;0 -2;-3 1",3.6,"0;0.25;0.5;0.75;1");
    if(mood==="excited")return move(ctx,"0 0;0 -3;0 0;0 -2;0 0;0 0",3.2,"0;0.16;0.3;0.44;0.6;1");
    return move(ctx,"0 0;0 0;0 -1;0 0;0 0",8,"0;0.3;0.4;0.6;1");
  }
  const work={
    happy:["0 0;-2 -2;2 0;0 2;0 0",2.4,"0;0.2;0.4;0.6;1"],
    excited:["0 0;0 3;0 -4;0 3;0 -4;0 0;0 0",1.6,"0;0.16;0.3;0.44;0.58;0.75;1"],
    proud:["0 0;0 0;5 -4;5 -4;0 0",4.4,"0;0.3;0.45;0.7;1"],
    curious:["-3 1;0 -2;3 1;0 -2;-3 1",2.8,"0;0.25;0.5;0.75;1"],
    determined:["0 0;0 2;0 0;0 2;0 0",1.8,"0;0.2;0.4;0.6;1"],
    grumpy:["0 0;0 -4;-2 4;2 1;0 -3;2 4;-2 1;0 0",1.2,"0;0.12;0.25;0.38;0.5;0.62;0.75;1"],
    sad:["0 0;0 2;-2 0;2 1;0 0;0 0",3.2,"0;0.2;0.3;0.4;0.55;1"]
  };
  return move(ctx,...work[mood]);
}
function face(ctx) {
  let art=group((ctx.gazeMotion||"")+eyes(ctx),'data-part="gaze"')+cheeks(ctx);
  const lips=ctx.mood==="sad"&&!ctx.quiet&&ctx.state!=="listening"?group(move(ctx,"0 0;1 0;-1 0;0 0;0 0",2.1,"0;0.2;0.3;0.4;1")+mouth(ctx)):mouth(ctx);
  art+=group(lips,"data-part=\"mouth\"");
  if(!ctx.quiet&&ctx.mood==="sad")art+=ctx.tearOverride!==undefined?ctx.tearOverride:tears(ctx);
  if(!ctx.quiet&&ctx.mood==="grumpy")art+=anger(ctx);
  if(!ctx.quiet&&!ctx.suppressDecor&&ctx.mood==="happy")art+=group(
    at(268,43,group(opacity(ctx,"1;0;1;1",2.4,"0;0.32;0.56;1")+move(ctx,"0 0;0 -3;0 0;0 0",2.4,"0;0.35;0.6;1")+star(0,0,16,ctx.complete?ctx.ink:palette.amber)))+
    at(48,49,group(opacity(ctx,"0;1;0;0",2.4,"0;0.25;0.65;1")+star(0,0,8,ctx.complete?ctx.ink:palette.amber))),'data-part="outer-sparkles"');
  if(!ctx.quiet&&!ctx.suppressDecor&&ctx.mood==="proud")art+=at(277,106,group(opacity(ctx,"1;1;0;1",4.4,"0;0.3;0.5;1")+star(0,0,16,ctx.ink)));
  const y=ctx.state==="needs_you"?24:ctx.complete?8:0;
  return at(0,y,group(faceMotion(ctx)+art,"data-part=\"face\""));
}
function keyboardBase(ctx) {
  let art=block(83,170,154,29,palette.dim)+rect(87,172,146,22,palette.black);
  const period={happy:1.2,excited:.72,proud:1.6,curious:1.8,determined:1,grumpy:.95,sad:1.7}[ctx.mood];
  for(let row=0;row<2;row++)for(let col=0;col<10;col++){
    const x=90+col*14,y=175+row*9;
    art+=rect(x,y,10,5,palette.dim);
    if((row+col)%3===0)art+=group(opacity(ctx,col%2?"0;1;0;0":"1;0;0;1",period,"0;0.25;0.5;1")+rect(x,y+1,10,4,palette.ink),`opacity="${col%2?0:1}"`);
  }
  return art+rect(129,194,62,3,palette.prop);
}
function dustPuff(x,y,ctx,delay=0) {
  const direction=delay?1:-1;
  return at(x,y,group(Array.from({length:5},(_,i)=>{
    const size=[8,5,6,4,3][i],dx=direction*(9+i*6),dy=-6-i*5;
    const phase=-i*.16-delay*.35;
    return group(opacity(ctx,"1;1;1;0;1",1.1,"0;0.23;0.6;0.9;1","indefinite",phase)+
      move(ctx,`0 0;${Math.round(dx*.5)} ${dy};${dx} ${dy+5};${dx} ${dy+12};0 0`,1.1,"0;0.23;0.5;0.9;1","indefinite",phase)+
      rect(i%2*5,i%3*4,size,size,i%2?palette.dim:palette.prop),'opacity="0"');
  }).join(""),'data-part="square-dust"'));
}
function keycap(size,letter="X") {
  const unit=size/8, glyph=letter==="X"?[[2,2],[4,2],[3,3],[2,4],[4,4]]:[[2,2],[3,2],[4,2],[2,3],[3,3],[2,4],[3,4],[4,4]];
  return rect(0,0,size,size,palette.prop)+rect(0,0,size-unit,size-unit,palette.ink)+glyph.map(([x,y])=>rect(x*unit,y*unit,unit,unit,palette.dark)).join("");
}
function flyingKeys(ctx) {
  let art="";
  for(let i=0;i<12;i++) {
    const right=i>=6, n=i%6,x=(right?174:96)+n*10,y=175+i%2*7;
    const dx=(right?1:-1)*[55,72,84,44,65,90][n],dy=-[38,53,31,61,42,48][n];
    const safeDx=right?Math.min(dx,305-x):Math.max(dx,9-x);
    const phase=-i*.145,seconds=1.8;
    art+=at(x,y,group(opacity(ctx,"1;1;1;1;0;1",seconds,"0;0.2;0.4;0.7;0.9;1","indefinite",phase)+
      move(ctx,`0 0;${Math.round(safeDx*.45)} ${dy};${Math.round(safeDx*.7)} ${dy-4};${safeDx} ${dy+19};${safeDx} 22;0 0`,seconds,"0;0.2;0.4;0.7;0.9;1","indefinite",phase)+
      keycap(i%4===0?16:8,i%2?"E":"X"),'opacity="0" data-part="sideways-key"'));
    if(i%2===0)art+=at(x,y,group(
      move(ctx,`0 0;${Math.round(safeDx*.7)} ${dy+8};${safeDx} 8;0 0`,1.2,"0;0.3;0.85;1","indefinite",phase)+
      opacity(ctx,"1;1;0;1",1.2,"0;0.3;0.85;1","indefinite",phase)+rect(0,0,4,4,palette.prop),'opacity="0" data-part="broken-key-fragment"'));
  }
  // Draw depth as three integer-sized sprites, never a blurry scale transform.
  for(let volley=0;volley<2;volley++)for(const [i,size]of[8,16,24].entries())art+=group(
    opacity(ctx,`${i===0?1:0};${i===1?1:0};${i===2?1:0};0;${i===0?1:0}`,1.8,"0;0.2;0.4;0.66;1","indefinite",-volley*.9)+
    at(volley?164+i*18:152-i*20,184+i*9,keycap(size,"X")),`opacity="0" data-part="approaching-key" data-size="${size}" data-volley="${volley}"`);
  return group(art,"data-part=\"flying-keycaps\"");
}
function flood(ctx) {
  let art="";
  for(let row=0;row<3;row++){
    const tiles=Array.from({length:18},(_,i)=>rect(79+i*9,199-row*9,7,7,[palette.water,palette.blue,palette.water,palette.lightWater][(i+row)%4])).join("");
    art+=group((row?opacity(ctx,row===1?"0;1;1;0;0":"0;0;1;0;0",8.4,"0;0.2;0.45;0.82;1"):"")+tiles,`opacity="${row?0:1}" data-part="water-tiles" data-row="${row}"`);
  }
  for(const [x,dy]of[[110,0],[151,-2],[201,1]])art+=at(x,190+dy,group(move(ctx,"0 0;2 -4;-2 -11;2 -16;0 -10;0 0;0 0",8.4,"0;0.15;0.3;0.5;0.7;0.85;1")+keycap(8,"E")));
  art+=splash(ctx,101,191,-.3)+splash(ctx,219,193,-.9);
  art+=group(opacity(ctx,"0;0;1;0;0",8.4,"0;0.48;0.52;0.7;1")+rect(243,174,4,4,palette.amber)+rect(253,164,3,3,palette.amber)+rect(253,183,3,3,palette.amber),'opacity="0" data-part="comic-short-circuit"');
  return group(art,"data-part=\"keyboard-flood\"");
}
function work(ctx) {
  const mood=ctx.mood;
  let boardMotion="";
  if(mood==="grumpy")boardMotion=move(ctx,"-3 0;3 3;-3 1;3 4;-3 0",.6,"0;0.25;0.5;0.75;1");
  else if(mood==="excited")boardMotion=move(ctx,"0 0;0 2;0 0;0 2;0 0",.8,"0;0.25;0.5;0.75;1");
  else if(mood==="sad")boardMotion=move(ctx,"0 0;-2 0;2 1;-3 1;0 0;0 0",8.4,"0;0.3;0.5;0.7;0.85;1");
  let art=group(boardMotion+keyboardBase(ctx),"data-part=\"keyboard\"");
  if(mood==="grumpy")art+=dustPuff(73,178,ctx)+dustPuff(237,178,ctx,1)+flyingKeys(ctx)+group(opacity(ctx,"1;0;1;0;1",.6,"0;0.2;0.5;0.7;1")+rect(145,158,5,5,palette.amber)+rect(162,152,5,5,palette.amber)+rect(174,160,5,5,palette.amber),'opacity="0"');
  if(mood==="sad")art+=flood(ctx);
  if(mood==="excited")art+=group(move(ctx,"0 0;2 0;0 0;-2 0;0 0",.8,"0;0.25;0.5;0.75;1")+[59,68,247,256].map((x,i)=>rect(x,175+i%2*8,4,4,palette.prop)).join("")+star(264,151,16,palette.amber),'data-part="speed-pixels"');
  if(mood==="happy")art+=at(263,160,group(move(ctx,"0 0;0 -3;0 -5;0 0;0 0",2.4,"0;0.25;0.45;0.65;1")+path("M8 0h5v15H5v-5h3Zm5 0h9v5h-9Z",palette.cheek)));
  if(mood==="proud")art+=at(246,158,group(opacity(ctx,"0;1;1;0;0",4.4,"0;0.42;0.56;0.75;1")+star(0,0,24,palette.amber),"opacity=\"0\""));
  if(mood==="curious") {
    const glass=path("M5 0h16v5h5v16h-5v5H5v-5H0V5h5Zm2 6v14h12V6Z",palette.blue)+path("M22 21h5v5h5v5h-6v-5h-4Z",palette.prop);
    art+=at(239,157,group(move(ctx,"0 0;-5 3;0 0;4 -4;0 0",2.8,"0;0.25;0.5;0.75;1")+glass,"data-part=\"inspection-glass\""));
  }
  if(mood==="determined")art+=rect(73,170,4,17,palette.blue)+rect(243,170,4,17,palette.blue);
  return art;
}
function request(ctx) {
  const question=["curious","sad"].includes(ctx.mood);
  let tile=path("M0 0h60v39H29v8h-8v-8H0Z",palette.amber)+rect(4,4,52,31,palette.black);
  if(question)tile+=path("M19 8h19v5h5v9h-6v5h-8v-8h8v-5H23v5h-6v-6h2Zm9 22h8v5h-8Z",palette.amber);
  else tile+=rect(13,16,6,6,palette.amber)+rect(27,16,6,6,palette.amber)+rect(41,16,6,6,palette.amber);
  const tap=group(move(ctx,"0 0;-4 0;0 0;-4 0;0 0;0 0",1.9,"0;0.2;0.35;0.5;0.65;1","1")+block(67,17,10,10,palette.ink)+rect(60,11,4,4,palette.amber)+rect(60,30,4,4,palette.amber),"data-part=\"knock\"");
  return at(24,23,group(move(ctx,"0 3;0 -2;0 0;0 0",1.2,"0;0.25;0.5;1","1")+tile+tap,"data-part=\"request-cue\""));
}
function trophy(ctx) {
  const cup=path("M9 0h28v6h8v15h-9v6h-7v9h10v6H7v-6h10v-9h-7v-6H1V6h8Z",ctx.ink)+
    path("M13 4h20v15h-5v5H18v-5h-5Z",palette.ink)+rect(5,10,5,7,palette.gold)+rect(36,10,5,7,palette.gold)+rect(20,26,6,10,palette.ochre)+rect(12,37,22,2,palette.ink);
  return at(137,14,group(move(ctx,"0 8;0 2;0 -3;0 0;0 0",1.6,"0;0.2;0.4;0.7;1","1")+cup,"data-part=\"trophy\""));
}
function firework(ctx,x,y,delay,color) {
  if(!ctx.motion)return at(x,y,star(-8,-8,16,color));
  let rays="";
  for(const [dx,dy]of [[0,-24],[16,-16],[24,0],[16,16],[0,24],[-16,16],[-24,0],[-16,-16]]) {
    rays+=group(move(ctx,`0 0;${Math.round(dx*.45)} ${Math.round(dy*.45)};${dx} ${dy};${dx} ${dy+5};${dx} ${dy+5}`,1.1,"0;0.25;0.5;0.75;1","1",delay)+rect(-2,-2,4,4,color));
  }
  return at(x,y,group(opacity(ctx,"0;1;1;0;0",1.1,"0;0.05;0.65;0.95;1","1",delay)+rays,"opacity=\"0\" data-part=\"firework\""));
}
function goldCycle(ctx) {
  if(!ctx.motion)return "";
  // Hue motion is deliberately slow and similar in brightness, not a strobe.
  return '<animate attributeName="fill" values="#FFD54A;#FFC94A;#FFB84A;#FFC94A;#FFD54A" keyTimes="0;0.25;0.5;0.75;1" dur="6.4s" repeatCount="indefinite" calcMode="linear"/>';
}
function victoryBackground(ctx) {
  let art=`<rect width="320" height="240" fill="${palette.gold}" data-part="victory-color">${goldCycle(ctx)}</rect>`;
  // Square lanes travel only along the perimeter, leaving the face uncluttered.
  for(const [cornerX,cornerY,dir]of[[0,0,1],[272,0,-1],[0,192,-1],[272,192,1]]) {
    let lane="";
    for(let i=0;i<4;i++)lane+=rect(i*12,i*12,8,8,i%2?"#FFE575":"#EEA638");
    art+=at(cornerX,cornerY,group(move(ctx,dir>0?"0 0;4 0;4 4;0 4;0 0":"4 4;0 4;0 0;4 0;4 4",1.6,"0;0.25;0.5;0.75;1")+lane,'data-part="victory-lane"'));
  }
  const bands=[0,1,2,3].map(phase=>{
    let tiles="";
    for(let i=0;i<10;i++) {
      const x=70+i*18,y=208+((i+phase)%3)*9;
      tiles+=rect(x,y,6,6,(i+phase)%2?"#FFE575":"#EEA638");
    }
    return tiles;
  });
  return group(art+frames(ctx,bands,1.6,"victory-rhythm"),'data-part="victory-background"');
}
function celebration(ctx) {
  let art=victoryBackground(ctx);
  art+=firework(ctx,38,56,.1,palette.red)+firework(ctx,282,28,.7,palette.ink)+firework(ctx,39,176,1.4,palette.dark)+firework(ctx,280,178,2.1,palette.blue);
  if(ctx.motion) {
    for(const [x,y,color] of [[24,69,palette.blue],[53,115,palette.red],[271,113,palette.dark],[300,71,palette.red],[120,23,palette.ink],[194,24,palette.blue]]) {
      art+=at(x,y,group(opacity(ctx,"0;1;1;0;0",4.8,"0;0.1;0.55;0.9;1","1")+move(ctx,"0 0;3 6;-3 14;4 24;0 34;0 34",4.8,"0;0.2;0.4;0.6;0.8;1","1")+rect(0,0,4,4,color),"opacity=\"0\" data-part=\"confetti\""));
    }
  }
  return art;
}
function listening(ctx) {
  return group(path("M141 175h8v4h-4v11h4v4h-8Z",palette.blue)+path("M171 175h8v19h-8v-4h4v-11h-4Z",palette.blue)+rect(157,181,6,6,palette.blue),"data-part=\"listening-cue\"");
}
function disconnected(ctx) {
  return group(path("M145 174h9v3h-6v8h6v3h-9ZM166 174h9v14h-9v-3h6v-8h-6Z",palette.dim)+rect(154,177,3,3,palette.dim)+rect(163,182,3,3,palette.dim)+rect(158,172,3,3,palette.dim)+rect(158,189,3,3,palette.dim),"data-part=\"disconnected-cue\"");
}
function scene(ctx) {
  let art=ctx.complete?celebration(ctx):"";
  art+=face(ctx);
  if(ctx.state==="working")art+=work(ctx);
  if(ctx.state==="needs_you")art+=request(ctx);
  if(ctx.complete)art+=trophy(ctx);
  if(ctx.state==="listening")art+=listening(ctx);
  if(ctx.state==="no_app")art+=disconnected(ctx);
  if(ctx.state==="asleep")art+=path("M270 64h14v3h-4v3h-4v3h8v3h-14v-3h4v-3h4v-3h-8Z",palette.dim);
  // Gold cut-outs in eyelids and the trophy must track the moving background.
  return ctx.complete&&ctx.motion?art.replace(/<(rect|path)([^>]* fill="#FFD54A"[^>]*)\/>/g,(_,tag,attrs)=>`<${tag}${attrs}>${goldCycle(ctx)}</${tag}>`):art;
}
function renderSVG(mood,state) {
  if(!moods.includes(mood)||!states.includes(state))throw new Error("Unknown Boop mood/state");
  const quiet=["asleep","no_app"].includes(state),complete=state==="task_complete";
  const ctx={mood:quiet?"happy":mood,state,quiet,complete,motion:true,ink:complete?palette.dark:palette.ink,bg:complete?palette.gold:palette.black,cheek:complete?"#D8576C":palette.cheek};
  const id=`boop-v4-${mood}-${state}`;
  const desc=quiet?`Shared ${label(state)} face, independent of mood.`:`${label(mood)} Boop, ${label(state)}. Exaggerated pixel expression with mood-specific motion. Silent base-design review.`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="${id}" data-mood="${mood}" data-state="${state}" data-revision="4" role="img" aria-labelledby="${id}-title ${id}-desc" shape-rendering="crispEdges">\n<title id="${id}-title">${label(mood)} · ${label(state)}</title>\n<desc id="${id}-desc">${esc(desc)}</desc>\n<style>#${id} .boop-still{display:none}@media(prefers-reduced-motion:reduce){#${id}:not([data-motion="on"]) .boop-motion{display:none}#${id}:not([data-motion="on"]) .boop-still{display:inline}}</style>\n<rect data-part="background" width="320" height="240" fill="${ctx.bg}"/>\n<g class="boop-motion">${scene(ctx)}</g>\n<g class="boop-still">${scene({...ctx,motion:false})}</g>\n</svg>\n`;
}
// V4 drawing primitives are reused by the internal variation renderer.

return {moods,states,palette,label,renderSVG,rect,path,block,group,at,animate,move,opacity,frames,fourEye,star,eyePose,eyes,mouth,face,keyboardBase,work,request,trophy,firework,goldCycle,victoryBackground,celebration,listening,disconnected,splash,tears,flood,dustPuff,flyingKeys,keycap};},
"visual/loop.mjs":()=>{
// Compile independent SMIL tracks onto one asset-local clock. No JS runtime
// is embedded in the SVG. Repeating the SVG N times repeats every track N times.
function loopSpec(mood,state,variant,workSeconds){
  let seconds=state==="working"?(mood==="sad"&&variant===1?6.4:workSeconds):
    ({idle:[8,10,9],needs_you:[6,7.2,6.4],task_complete:[6.4,7.2,6.4],listening:[6.4,7.2,6.8],asleep:[9,10,12],no_app:[9,10,12]})[state][variant-1];
  return {seconds,seam_hold_seconds:.04,default_repeat_count:"indefinite",recommended_repeat_count:["needs_you","task_complete"].includes(state)?1:"indefinite",boundary:"Same complete frame at start, end and finite stop; effects share the clip clock"};
}
const num=n=>String(Number(n.toFixed(8)));
function sample(values,times,p,linear){
  let i=0;while(i+1<times.length&&times[i+1]<=p+1e-9)i++;
  if(!linear||i===times.length-1)return values[i];
  const f=(p-times[i])/(times[i+1]-times[i]);
  if(/^#[0-9a-f]{6}$/i.test(values[i])){
    const rgb=v=>[1,3,5].map(k=>parseInt(v.slice(k,k+2),16));
    return "#"+rgb(values[i]).map((c,k)=>Math.round(c+(rgb(values[i+1])[k]-c)*f).toString(16).padStart(2,"0")).join("");
  }
  return num(Number(values[i])+(Number(values[i+1])-Number(values[i]))*f);
}
function returnValues(from,to,attribute){
  if(attribute!=="transform")return [to];
  const a=from.split(/\s+/).map(Number),b=to.split(/\s+/).map(Number);
  return [.33,.67,1].map(f=>a.map((v,i)=>Math.round(v+(b[i]-v)*f)).join(" "));
}
function closeTimelines(art,seconds,repeatCount="indefinite"){
  if(repeatCount!=="indefinite"&&(!Number.isInteger(repeatCount)||repeatCount<1||repeatCount>100))throw new Error("repeatCount must be 1–100 or indefinite");
  const guard=.04;
  return art.replace(/<(animate|animateTransform)\b([^>]*?)\/>/g,(_,tag,attrs)=>{
    const a=Object.fromEntries([...attrs.matchAll(/([\w:-]+)="([^"]*)"/g)].map(m=>[m[1],m[2]]));
    const values=a.values.split(";"),times=a.keyTimes.split(";").map(Number),duration=parseFloat(a.dur),begin=parseFloat(a.begin||"0"),linear=a.calcMode==="linear";
    const oneShot=a.repeatCount==="1";
    let events=[],at;
    if(oneShot){
      // Keep the action in forward order. If a pose changes, recover during the
      // unused tail; burst transforms may reset while their parent is hidden.
      const end=Math.min(begin+duration,seconds-.55),scale=(end-Math.max(0,begin))/duration;
      const start=Math.max(0,begin);
      events=times.map((p,i)=>[start+p*duration*scale,values[i]]);
      if(start>0)events.unshift([0,values[0]]);
      if(values.at(-1)!==values[0]){
        const recovery=returnValues(values.at(-1),values[0],a.attributeName);
        recovery.forEach((v,i)=>events.push([seconds-.44+(i+1)*.1,v]));
      }
      at=t=>{
        let i=0;while(i+1<events.length&&events[i+1][0]<=t+1e-9)i++;
        return events[i][1];
      };
    }else{
      // Fit a whole number of local cycles, retaining relative particle phase.
      const cycles=Math.max(1,Math.round(seconds/duration)),period=seconds/cycles,phase=begin/duration;
      at=t=>{let p=((t/period-phase)%1+1)%1;return sample(values,times,p,linear);};
      for(let k=Math.floor(-phase)-1;k<=cycles+Math.ceil(Math.abs(phase))+1;k++)for(const p of times){
        const t=(k+p+phase)*period;if(t>0&&t<seconds)events.push([t,at(t)]);
      }
    }
    const initial=at(0);
    const points=[[0,initial],[guard,initial],...events.filter(([t])=>t>guard&&t<seconds-guard),[seconds-guard,initial],[seconds,initial]];
    points.sort((a,b)=>a[0]-b[0]);
    const compact=[];
    for(const point of points){
      if(compact.length&&Math.abs(point[0]-compact.at(-1)[0])<1e-7)compact[compact.length-1]=point;
      else compact.push(point);
    }
    a.values=compact.map(p=>p[1]).join(";");a.keyTimes=compact.map(p=>num(p[0]/seconds)).join(";");
    a.dur=num(seconds)+"s";a.begin="0s";a.repeatCount=String(repeatCount);a.fill="freeze";
    return `<${tag} ${Object.entries(a).map(([k,v])=>`${k}="${v}"`).join(" ")}/>`;
  });
}

return {loopSpec,closeTimelines};},
"visual/performances.mjs":()=>{
// Internal acting recipes. These are not extra agent/tool parameters.
// Canonical catalog IDs are retained; newer owner feedback overrides old art limits.
const workCaptions={
  happy:["Even paired taps · soft bob","Notes drift upward · mouth hums","Compress → key tap → rebound","Typing continues through a sideways peek","Three tiles snap into a tidy row"],
  excited:["Fast staccato taps · little breath","Rapid left / center / right shuffle","Alternating key flurries · side ticks","Eager glance → snap back to work","Coil downward → spring into a flurry"],
  proud:["Sparse taps · slow audience glance","Square flourish over the last key","Precise alignment · measured scan","Peek → blush → tuck away","A showy tap knocks one key crooked"],
  curious:["Lens and brackets inspect one tile","Look left / right between two tiles","Sparkle → pause → try the keyboard","Follow a bounded wandering square","Peer at the same tile from both sides"],
  determined:["Steady planted typing","Pull back → press forward","Scan three rows, then start again","Steadying breath → recenter","Slow emphatic key press"],
  grumpy:["Unbroken key spray · rattling keyboard","Large cap catapult + smaller debris","Dust blocks boil around the keys","Accusatory scan → firm key jab","Huff pixels drift off · chaos continues"],
  sad:["Wide cube tears feed a tiled flood","Sniffle → flick off one tear","Large tear obscures just one eye","Typing through sobbing beats","Retain corner tears · brace to continue"]
};
const workRecipes={
  happy:[
    {name:"Easy rhythm",prop:"keyboard",beat:"0 0;-2 -2;2 0;0 2;0 0",seconds:3.2,fx:"twinkle"},
    {name:"Singing along",prop:"keyboard",beat:"-3 0;3 -2;-3 0;3 -2;-3 0",seconds:3.2,fx:"music",mouth:"sing"},
    {name:"Bouncy return key",prop:"keyboard",beat:"0 0;0 -4;0 7;0 -7;0 0",seconds:4,fx:"big-key"},
    {name:"Friendly audience check",prop:"keyboard",beat:"0 0;0 0;4 -2;4 -2;0 0",gaze:"0 0;0 0;5 -2;5 -2;0 0",seconds:5.6,fx:"none"},
    {name:"Neat little shuffle",prop:"tiles",beat:"-3 0;3 0;-2 0;0 -2;0 0",seconds:4.8,fx:"none"}
  ],
  excited:[
    {name:"Turbo typing",prop:"keyboard",beat:"0 0;0 4;0 -5;0 4;0 0",seconds:1.6,fx:"speed"},
    {name:"Rapid-fire sorting",prop:"tiles",beat:"-5 0;0 2;5 0;0 -2;-5 0",gaze:"-4 0;0 0;4 0;0 0;-4 0",seconds:2,fx:"speed"},
    {name:"Keyboard overdrive",prop:"double-keyboard",beat:"0 0;-4 3;4 3;0 -3;0 0",seconds:1.2,fx:"speed"},
    {name:"Eager double-take",prop:"keyboard",beat:"0 0;6 -4;0 5;-3 1;0 0",gaze:"0 0;6 -2;0 2;0 0;0 0",seconds:3.2,fx:"turn-tick"},
    {name:"Coiled little engine",prop:"keyboard",beat:"0 0;0 8;0 10;0 -9;0 0",seconds:3.6,fx:"spring"}
  ],
  proud:[
    {name:"Effortless expert",prop:"keyboard",beat:"0 0;0 -2;4 -3;4 -3;0 0",gaze:"0 0;0 0;5 -1;5 -1;0 0",seconds:6.4,fx:"none"},
    {name:"Watch this flourish",prop:"keyboard",beat:"0 0;0 -4;0 3;5 -3;0 0",seconds:4.4,fx:"key-arc"},
    {name:"Immaculate professional",prop:"tiles",beat:"-2 0;0 0;2 0;0 -2;0 0",seconds:5.6,fx:"straighten"},
    {name:"Bashful show-off",prop:"keyboard",beat:"0 -3;4 -3;0 7;-2 4;0 0",gaze:"0 0;4 0;0 2;-2 1;0 0",seconds:5.2,fx:"blush"},
    {name:"Too grand for the key",prop:"keyboard",beat:"0 0;0 -5;3 5;-4 2;0 0",seconds:5.6,fx:"crooked-key"}
  ],
  curious:[
    {name:"Close inspection",prop:"inspect",beat:"0 0;7 3;7 4;2 1;0 0",gaze:"0 0;4 2;4 3;0 0;0 0",seconds:4.4,fx:"glass"},
    {name:"Compare the clues",prop:"compare",beat:"-6 1;-6 1;6 1;6 1;-6 1",gaze:"-4 2;-4 2;4 2;4 2;-4 2",seconds:4,fx:"none"},
    {name:"Interesting possibility",prop:"keyboard",beat:"0 0;0 -6;0 -6;0 4;0 0",seconds:4.8,fx:"idea"},
    {name:"Follow that cursor",prop:"cursor",beat:"-4 0;6 -2;8 3;-5 1;-4 0",gaze:"-5 0;5 -2;7 2;-4 0;-5 0",seconds:4,fx:"none"},
    {name:"Peer around the problem",prop:"inspect",beat:"-9 2;-9 4;9 2;9 4;0 0",gaze:"-3 1;-3 2;3 1;3 2;0 0",seconds:5.2,fx:"brackets"}
  ],
  determined:[
    {name:"Steady little engine",prop:"keyboard",beat:"0 2;0 4;0 2;0 4;0 2",seconds:2,fx:"brackets"},
    {name:"Brace and push",prop:"keyboard",beat:"0 0;0 -5;0 7;0 4;0 0",seconds:4.4,fx:"pressure"},
    {name:"Methodical pass",prop:"rows",beat:"-3 0;0 1;3 2;0 0;-3 0",gaze:"-4 0;0 1;4 2;0 0;-4 0",seconds:4.8,fx:"none"},
    {name:"Refocus and continue",prop:"keyboard",beat:"0 0;0 -4;0 -4;0 4;0 0",seconds:5.6,fx:"breath"},
    {name:"Heroic final key",prop:"keyboard",beat:"0 0;0 -7;0 6;0 -3;0 0",seconds:5.2,fx:"big-key"}
  ],
  grumpy:[
    {name:"Keyboard meltdown",prop:"chaos",beat:"0 0;0 -4;-2 4;2 1;0 0",seconds:1.2,fx:"none"},
    {name:"Keycap catapult",prop:"keyboard",beat:"0 -3;0 6;-3 1;3 3;0 -3",seconds:1.6,fx:"catapult"},
    {name:"Dust-cloud tussle",prop:"keyboard",beat:"-4 2;4 6;-4 6;4 2;-4 2",seconds:1.4,fx:"dust-storm"},
    {name:"Suspicious inspection",prop:"rows",beat:"-4 0;0 0;7 5;7 5;0 0",gaze:"-4 0;0 0;5 3;5 3;0 0",seconds:4,fx:"accuse"},
    {name:"Huff and carry on",prop:"keyboard",beat:"0 0;0 -6;0 -4;0 5;0 0",seconds:3.6,fx:"huff"}
  ],
  sad:[
    {name:"Typing through a flood",prop:"flood",beat:"0 0;0 2;-2 0;2 1;0 0",seconds:3.2,tear:"waterfall",fx:"none"},
    {name:"Sniffle and refocus",prop:"keyboard",beat:"0 3;0 -4;-4 -2;4 -2;0 3",seconds:4.4,tear:"flick",fx:"breath"},
    {name:"One eye on the job",prop:"keyboard",beat:"-5 2;-5 2;3 1;0 -3;-5 2",seconds:4.8,tear:"lens",fx:"none"},
    {name:"Whiny work rhythm",prop:"flood",beat:"0 2;-3 5;0 2;3 5;0 2",seconds:2.4,tear:"waterfall",fx:"sob"},
    {name:"Brave little reset",prop:"keyboard",beat:"0 6;0 6;0 -5;0 2;0 0",seconds:5.6,tear:"corners",fx:"pressure"}
  ]
};

// Poses are five integer-aligned acting beats; entries hold their final pose.
const requestBeats={
  happy:["0 0;-5 -2;3 -3;0 0;0 0","0 0;5 2;-2 -2;0 0;0 0","0 4;0 7;-2 1;0 0;0 0"],
  excited:["0 0;0 -8;0 3;0 0;0 0","0 0;0 -5;0 4;0 0;0 0","-4 0;4 -3;-3 -2;0 0;0 0"],
  proud:["0 -3;-5 -3;5 1;0 -2;0 -2","3 -3;3 -3;-3 0;0 -2;0 -2","-4 -2;-4 -2;4 0;0 -1;0 -1"],
  curious:["0 0;-6 2;3 -2;0 0;0 0","5 3;7 4;0 -3;0 0;0 0","-8 2;-8 2;5 -2;0 0;0 0"],
  determined:["0 3;0 -2;0 1;0 0;0 0","-3 0;3 -2;0 -3;0 0;0 0","0 4;0 4;0 -4;0 0;0 0"],
  grumpy:["0 1;0 7;-3 2;0 0;0 0","5 1;5 1;-5 0;0 0;0 0","0 -4;0 -4;0 3;0 0;0 0"],
  sad:["0 4;-5 4;0 1;0 0;0 0","0 7;0 7;0 -3;0 0;0 0","-6 7;-6 7;1 2;0 0;0 0"]
};
const completeBeats={
  happy:["0 0;0 -5;0 3;0 0;0 0","0 0;-7 -3;7 -3;0 0;0 0","0 -5;0 -5;0 4;0 0;0 0"],
  excited:["0 0;0 -12;0 5;0 -4;0 0","-7 0;7 -6;-7 0;0 -3;0 0","0 -8;0 4;0 4;0 -3;0 0"],
  proud:["0 -3;0 9;0 12;3 2;0 0","0 0;0 -6;-3 -3;3 -3;0 0","0 -5;0 -5;0 8;0 3;0 0"],
  curious:["5 3;5 3;-4 -2;0 0;0 0","0 0;6 3;6 3;-3 -2;0 0","-4 4;0 -5;4 -2;0 0;0 0"],
  determined:["0 3;0 -4;0 5;0 0;0 0","0 3;0 -6;0 -6;0 2;0 0","-3 1;3 1;0 -3;0 0;0 0"],
  grumpy:["0 0;0 -3;0 6;0 1;0 0","0 0;-5 1;5 1;0 0;0 0","-3 1;-3 1;3 -2;0 0;0 0"],
  sad:["0 4;0 4;-2 1;0 -2;0 0","0 0;0 10;-3 7;2 2;0 0","0 6;0 -5;0 -5;0 3;0 0"]
};
const listeningBeats={
  happy:["0 0;0 -2;0 -2;0 0;0 0","-4 0;-2 -3;-2 -3;0 0;0 0","3 1;3 1;0 0;0 0;0 0"],
  excited:["0 0;0 -5;0 1;0 0;0 0","4 -2;4 -2;0 0;0 0;0 0","0 0;0 -4;0 2;0 0;0 0"],
  proud:["0 -4;0 -4;0 -1;0 0;0 0","-4 -2;-4 -2;0 0;0 0;0 0","0 -5;0 -5;0 1;0 0;0 0"],
  curious:["-5 1;-5 1;-2 -2;0 0;0 0","5 2;5 2;1 0;0 0;0 0","-4 2;4 -2;0 0;0 0;0 0"],
  determined:["0 1;0 0;0 0;0 0;0 0","0 0;0 -3;0 -3;0 0;0 0","0 3;0 3;0 -1;0 0;0 0"],
  grumpy:["2 2;0 1;0 0;0 0;0 0","5 0;5 0;-2 -2;0 0;0 0","0 4;0 4;0 -1;0 0;0 0"],
  sad:["0 2;0 1;0 0;0 0;0 0","0 6;0 6;0 -2;0 0;0 0","0 0;0 -2;1 2;0 0;0 0"]
};

return {workCaptions,workRecipes,requestBeats,completeBeats,listeningBeats};},
"visual/renderer.mjs":()=>{
const {moods,states,palette,label,rect,path,block,group,at,move,opacity,frames,star,eyePose,mouth,face,keyboardBase,work,request,trophy,celebration,victoryBackground,listening,disconnected,splash,tears,flood,dustPuff,flyingKeys,keycap}=load("visual/base.mjs");
const {workRecipes,requestBeats,completeBeats,listeningBeats}=load("visual/performances.mjs");
const {sceneSpecs,drawWorkScene,requestScene,completionScene,listeningScene,grumpyActing}=load("visual/scenes.mjs");
const {loopSpec,closeTimelines}=load("visual/loop.mjs");
const safe=s=>String(s).replaceAll("&","&amp;").replaceAll('"',"&quot;").replaceAll("<","&lt;");
const five="0;0.18;0.4;0.66;1";
const act=(ctx,poses,seconds=4,repeat="indefinite")=>move(ctx,poses,seconds,five,repeat);
const show=(ctx,art,values="0;1;1;0;0",seconds=4,repeat="indefinite")=>group(opacity(ctx,values,seconds,five,repeat)+art,`opacity="${values[0]}"`);
const cornerTears=()=>rect(79,110,5,5,palette.blue)+rect(232,110,5,5,palette.lightWater);

function tile(x,y,w=40,h=24,color=palette.dim) {
  return at(x,y,rect(0,0,w,h,color)+rect(3,3,w-6,h-6,palette.black)+rect(7,7,6,6,palette.prop)+rect(17,7,w-24,3,palette.dim)+rect(17,13,w-24,3,palette.dim));
}
function focus(x,y,w,h,color=palette.blue) {
  return at(x,y,path(`M0 7V0h7v3H3v4ZM${w-7} 0h7v7h-3V3h-4ZM0 ${h-7}h3v4h4v3H0ZM${w-3} ${h-7}h3v7h-7v-3h4Z`,color));
}
function effectSquares(ctx,x,y,color=palette.amber,seconds=3.2) {
  return at(x,y,group(act(ctx,"0 0;0 -3;0 -7;0 -10;0 0",seconds,ctx.complete?"1":"indefinite")+(ctx.complete?opacity(ctx,"1;1;1;0;0",seconds,five,"1"):"")+rect(0,0,4,4,color)+rect(11,-6,3,3,color)+rect(-10,-4,3,3,color)));
}
function music(ctx) {
  const note=rect(6,0,3,16,ctx.cheek)+rect(9,0,7,4,ctx.cheek)+rect(0,12,6,6,ctx.cheek);
  return group(at(31,158,group(move(ctx,"0 0;2 -6;-2 -14;1 -23;0 0",3.2,five)+note))+
    at(271,164,group(move(ctx,"0 -15;-2 -23;0 0;2 -7;0 -15",3.2,five)+note)),'data-part="singing-notes"');
}
function breath(ctx,seconds=4,color=palette.prop) {
  const squares=rect(0,0,5,5,color)+rect(8,-3,4,4,color)+rect(15,1,3,3,color);
  return at(189,144,show(ctx,group(act(ctx,"0 0;0 0;9 -3;20 -5;0 0",seconds)+squares),"0;1;1;0;0",seconds));
}
function tearTreatment(ctx,mode="sparse") {
  if(mode==="waterfall")return tears(ctx);
  if(mode==="none")return "";
  if(mode==="corners")return cornerTears();
  if(mode==="flick")return cornerTears()+at(80,112,show(ctx,group(act(ctx,"0 0;0 0;-13 17;-22 33;0 0",4.4)+rect(0,0,7,7,palette.blue)),"0;1;1;0;0",4.4));
  if(mode==="lens")return cornerTears()+at(70,84,group(
    move(ctx,"0 0;0 0;2 16;-12 51;0 0",4.8,five)+
    opacity(ctx,"1;1;1;0;1",4.8,five)+rect(0,0,24,24,palette.water)+rect(3,3,7,7,palette.lightWater)+rect(17,16,4,4,palette.blue),'data-part="big-tear"'));
  return tears({...ctx,state:"listening"});
}
function workProp(ctx,r) {
  const cycle=r.seconds;
  let art="";
  if(r.prop==="chaos")return group(work(ctx),'data-part="working-prop"');
  if(["keyboard","flood","double-keyboard"].includes(r.prop)) {
    const bounce=ctx.mood==="grumpy"?"-3 0;3 3;-3 1;3 4;-3 0":ctx.mood==="excited"?"0 0;0 2;0 0;0 2;0 0":"0 0;0 1;0 0;0 1;0 0";
    art+=group(act(ctx,bounce,ctx.mood==="grumpy"?.6:ctx.mood==="excited"?.8:1.6)+keyboardBase(ctx),'data-part="keyboard"');
    if(r.prop==="flood")art+=flood(ctx);
    if(r.prop==="double-keyboard")art+=group(act(ctx,"-6 0;6 0;-6 0;6 0;-6 0",.48)+rect(97,171,12,4,palette.ink)+rect(169,181,12,4,palette.ink)+rect(205,171,12,4,palette.ink));
  } else if(r.prop==="tiles") {
    for(const [i,x]of[95,142,189].entries())art+=at(x,177,group(move(ctx,`${(i-1)*9} ${i%2?8:-3};0 0;0 0;${(1-i)*6} 3;${(i-1)*9} ${i%2?8:-3}`,cycle,five)+tile(0,0,36,24)));
    art+=at(93,173,group(act(ctx,"0 0;47 0;94 0;47 0;0 0",cycle)+focus(0,0,40,32)));
  } else if(r.prop==="rows") {
    art+=rect(107,172,106,30,palette.dim)+rect(110,175,100,24,palette.black);
    for(let i=0;i<3;i++)art+=rect(125,177+i*7,74-i*8,3,palette.prop);
    art+=at(115,176,group(move(ctx,"0 0;0 7;0 14;0 7;0 0",cycle,five)+rect(0,0,4,4,palette.blue)));
  } else if(r.prop==="compare") {
    art+=tile(102,176,42,27)+tile(176,176,42,27);
    art+=group(act(ctx,"0 0;0 0;74 0;74 0;0 0",cycle)+focus(99,173,48,33));
  } else if(r.prop==="cursor") {
    art+=focus(103,171,115,34,palette.dim)+rect(122,187,32,3,palette.dim)+rect(172,179,19,3,palette.dim);
    art+=at(118,177,group(act(ctx,"0 0;65 1;80 18;15 18;0 0",cycle)+rect(0,0,6,6,palette.blue)));
  } else art+=tile(119,175,82,28)+focus(115,171,90,36);
  return group(art,'data-part="working-prop"');
}
function workEffect(ctx,r) {
  const s=r.seconds;
  switch(r.fx){
    case"music":return music(ctx);
    case"twinkle":return at(271,161,show(ctx,star(0,0,16,palette.amber),"0;1;0;0;0",s));
    case"speed":return group(act(ctx,"0 0;3 0;0 0;-3 0;0 0",.6)+[52,63,250,261].map((x,i)=>rect(x,176+i%2*8,4,4,palette.prop)).join(""));
    case"big-key":return at(154,179,show(ctx,group(act(ctx,"0 0;0 -2;0 6;0 -3;0 0",s)+keycap(16,"E")),"0;1;1;0;0",s))+at(157,164,show(ctx,star(0,0,8,palette.amber),"0;0;1;0;0",s));
    case"turn-tick":return at(278,135,show(ctx,rect(0,0,5,5,palette.amber)+rect(7,-7,4,4,palette.amber),"0;1;0;0;0",s));
    case"spring":return show(ctx,rect(74,171,5,5,palette.amber)+rect(74,181,5,5,palette.amber)+rect(243,171,5,5,palette.amber)+rect(243,181,5,5,palette.amber),"0;0;1;0;0",s);
    case"key-arc":return at(224,172,show(ctx,group(act(ctx,"0 0;-9 -13;-25 -19;-43 -8;0 0",s)+star(0,0,8,palette.amber)),"0;1;1;0;0",s));
    case"straighten":return show(ctx,rect(88,206,143,3,palette.blue),"0;0;1;0;0",s);
    case"blush":return show(ctx,rect(49,138,4,4,ctx.cheek)+rect(58,138,4,4,ctx.cheek)+rect(260,138,4,4,ctx.cheek)+rect(269,138,4,4,ctx.cheek),"0;0;1;1;0",s);
    case"crooked-key":return at(183,174,group(act(ctx,"0 0;0 0;5 -12;3 -3;0 0",s)+keycap(16,"E")));
    case"glass":return at(224,167,group(act(ctx,"0 0;-10 -4;-10 -4;0 0;0 0",s)+focus(0,0,24,24,palette.blue)+rect(23,21,5,5,palette.prop)+rect(27,25,5,5,palette.prop)));
    case"idea":return at(271,63,show(ctx,star(0,0,16,palette.amber),"0;1;1;0;0",s));
    case"brackets":return focus(74,170,172,31,palette.blue);
    case"pressure":return show(ctx,rect(76,174,4,4,palette.blue)+rect(242,174,4,4,palette.blue)+rect(77,185,4,4,palette.blue)+rect(241,185,4,4,palette.blue),"0;0;1;1;0",s);
    case"breath":return breath(ctx,s,ctx.mood==="sad"?palette.blue:palette.prop);
    case"catapult":return flyingKeys(ctx)+at(247,181,group(act(ctx,"0 0;8 -22;16 -10;8 14;0 0",s)+keycap(24,"E")));
    case"dust-storm":return flyingKeys(ctx)+[75,115,160,208,240].map((x,i)=>dustPuff(x,183,ctx,i%2)).join("");
    case"accuse":return at(232,170,show(ctx,group(act(ctx,"0 0;-4 -6;0 0;5 9;0 0",s)+keycap(16,"X")),"0;0;1;1;0",s));
    case"huff":return breath(ctx,s)+flyingKeys(ctx);
    case"sob":return show(ctx,rect(53,149,4,4,palette.blue)+rect(266,149,4,4,palette.blue),"0;1;0;1;0",s);
    default:return "";
  }
}
const glyphs={M:["10001","11011","10101","10101","10001","10001","10001"],W:["10001","10001","10001","10101","10101","11011","10001"],H:["10001","10001","10001","11111","10001","10001","10001"],A:["01110","10001","10001","11111","10001","10001","10001"]};
function comicText(text,size,color) {
  let art="";let x=0;
  for(const letter of text){for(const [row,line]of glyphs[letter].entries())for(let col=0;col<line.length;col++)if(line[col]==="1")art+=rect(x+col*size,row*size,size,size,color);x+=6*size;}
  return at(Math.floor((320-(x-size))/2),176,art);
}
function cackle(ctx) {
  if(!ctx.motion)return group(comicText("MWHAHAHA",4,ctx.ink),'data-part="comic-cackle"');
  return group([1,2,3,4].map((size,i)=>{
    const values=[0,0,0,0,0,0];values[i+1]=1;
    return group(opacity(ctx,values.join(";"),4.8,"0;0.1;0.27;0.45;0.65;1","1")+comicText("MWHAHAHA",size,ctx.ink),`opacity="0" data-size="${size}"`);
  }).join(""),'data-part="comic-cackle"');
}
function resultCard(ctx,variant) {
  if(ctx.mood==="proud"&&variant===2)return cackle(ctx);
  const y=183;
  let card=rect(0,0,54,23,ctx.ink)+rect(4,4,46,15,palette.ink)+rect(10,8,32,3,palette.dim)+rect(10,14,21,2,palette.dim);
  const entrance=variant===1?"0 14;0 8;0 0;0 0;0 0":variant===2?"24 0;12 0;0 0;0 0;0 0":"0 0;-3 0;3 0;0 0;0 0";
  return at(133,y,group(act(ctx,entrance,2.8,"1")+card,'data-part="result-card"'));
}
function makeContext(mood,state,variant) {
  const quiet=["asleep","no_app"].includes(state),complete=state==="task_complete";
  return {mood:quiet?"happy":mood,state,variant,quiet,complete,motion:true,ink:complete?palette.dark:palette.ink,bg:complete?palette.gold:palette.black,cheek:complete?"#D8576C":palette.cheek};
}
function drawing(input) {
  const ctx={...input},n=ctx.variant,m=ctx.mood,s=ctx.state;
  let art="";
  if(s==="working") {
    const r={...workRecipes[m][n-1],seconds:sceneSpecs[m][n-1][3]};
    ctx.actorMotion=m==="grumpy"&&n>1?grumpyActing(ctx):act(ctx,r.beat,r.seconds);
    ctx.gazeMotion=r.gaze?act(ctx,r.gaze,r.seconds):"";
    ctx.suppressDecor=["music","blush"].includes(r.fx);
    if(m==="sad")ctx.tearOverride=tearTreatment(ctx,n===3?"corners":"waterfall");
    if(r.mouth==="sing")ctx.mouthOverride=frames(ctx,[mouth(ctx),block(154,128,12,14,ctx.ink),mouth(ctx),block(155,128,10,10,ctx.ink)],3.2,"singing-mouth");
    art=face(ctx)+drawWorkScene(ctx);
  } else if(s==="needs_you") {
    ctx.actorMotion=act(ctx,requestBeats[m][n-1],n===1?2.4:3.4,"1");
    ctx.gazeMotion=act(ctx,n===1?"0 0;-4 -3;3 -1;0 0;0 0":n===2?"0 0;3 2;-3 -2;0 0;0 0":"-3 2;-3 2;3 -3;0 0;0 0",3.4,"1");
    ctx.tearOverride=tearTreatment(ctx,n===1?"flick":"corners");
    art=face(ctx)+request({...ctx,motion:false})+requestScene(ctx);
  } else if(s==="task_complete") {
    ctx.actorMotion=act(ctx,completeBeats[m][n-1],4.2,"1");
    ctx.gazeMotion=act(ctx,n===1?"0 0;0 2;0 2;3 -1;0 0":n===2?"-3 0;3 1;3 1;0 -1;0 0":"0 2;0 2;-2 1;0 -1;0 0",4.2,"1");
    ctx.tearOverride=tearTreatment(ctx,n===1?"flick":"corners");
    if(m==="proud"&&n===2)ctx.mouthOverride=group(opacity(ctx,"1;0;1;0;1",4.8,five,"1")+mouth(ctx))+show(ctx,block(143,130,34,16,ctx.ink),"0;1;0;1;0",4.8,"1");
    art=(n===1?celebration(ctx):victoryBackground(ctx))+face(ctx)+completionScene(ctx)+(m==="proud"&&n===2?cackle(ctx):"");
  } else if(s==="listening") {
    ctx.actorMotion=act(ctx,listeningBeats[m][n-1],4,"1");
    ctx.gazeMotion=n===2?act(ctx,"4 0;4 0;1 0;0 0;0 0",4,"1"):n===3?act(ctx,"-3 1;-3 1;0 0;0 0;0 0",3,"1"):"";
    ctx.tearOverride=tearTreatment(ctx,n===3?"flick":"corners");
    ctx.suppressDecor=true;
    art=face(ctx)+listeningScene(ctx)+listening(ctx);
  } else if(s==="idle") {
    ctx.actorMotion=n===3?act(ctx,"0 0;0 -4;0 3;0 1;0 0",9):"";
    ctx.gazeMotion=n===2?act(ctx,"0 0;-5 0;0 0;5 0;0 0",10):"";
    ctx.tearOverride=cornerTears();ctx.suppressDecor=true;
    art=face(ctx);
  } else {
    ctx.actorMotion=n===1?act(ctx,"0 0;0 -1;0 -2;0 -1;0 0",9):n===2?act(ctx,"0 0;0 0;-2 1;0 0;0 0",10):act(ctx,"0 0;0 4;3 4;2 1;0 0",12);
    if(n===2){
      const open=eyePose(ctx),twitch=s==="asleep"?block(68,95,40,3,ctx.ink)+block(212,93,40,5,ctx.ink):block(68,99,40,3,ctx.ink)+block(212,99,40,3,ctx.ink);
      ctx.eyeOverride=group(opacity(ctx,"1;0;1;1",10,"0;0.45;0.49;1")+open)+group(opacity(ctx,"0;1;0;0",10,"0;0.45;0.49;1")+twitch,'opacity="0"');
    }
    art=face(ctx)+(s==="no_app"?disconnected(ctx):at(271,65,path("M0 0h12v3H8v3H4v3h8v3H0V9h4V6h4V3H0Z",palette.dim)));
  }
  return ctx.complete&&ctx.motion?art.replace(/<(rect|path)([^>]* fill="#FFD54A"[^>]*)\/>/g,(_,tag,attrs)=>`<${tag}${attrs}><animate attributeName="fill" values="#FFD54A;#FFC94A;#FFB84A;#FFC94A;#FFD54A" keyTimes="0;0.25;0.5;0.75;1" dur="6.4s" repeatCount="indefinite" calcMode="linear"/></${tag}>`):art;
}
function renderVariation(mood,state,variant,name="",options={}) {
  if(!moods.includes(mood)||!states.includes(state)||!Number.isInteger(variant)||variant<1||variant>(state==="working"?5:3))throw new Error("Invalid internal asset key");
  const ctx=makeContext(mood,state,variant),id=`boop-var4-${mood}-${state}-${variant}`;
  const loop=loopSpec(mood,state,variant,state==="working"?sceneSpecs[mood][variant-1][3]:null);
  ctx.loopSeconds=loop.seconds;
  const repeatCount=options.repeatCount??loop.default_repeat_count;
  const title=`${label(mood)} · ${label(state)} · ${name||variant}`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" id="${id}" data-mood="${mood}" data-state="${state}" data-variant="${variant}" data-loop-seconds="${loop.seconds}" data-repeat-count="${repeatCount}" role="img" aria-labelledby="${id}-title ${id}-desc" shape-rendering="crispEdges" overflow="hidden"><title id="${id}-title">${safe(title)}</title><desc id="${id}-desc">Silent seamless-loop pixel-art variation. ${loop.seconds} seconds per cycle. ${ctx.quiet?"Shared quiet performance; mood ignored.":"Uses the approved V4 face identity."}</desc><style>#${id} .boop-still{display:none}@media(prefers-reduced-motion:reduce){#${id}:not([data-motion="on"]) .boop-motion{display:none}#${id}:not([data-motion="on"]) .boop-still{display:inline}}</style><defs><clipPath id="${id}-bounds"><rect width="320" height="240"/></clipPath></defs><rect width="320" height="240" fill="${ctx.bg}"/><g clip-path="url(#${id}-bounds)"><g class="boop-motion">${closeTimelines(drawing(ctx),loop.seconds,repeatCount)}</g><g class="boop-still">${drawing({...ctx,motion:false})}</g></g></svg>\n`;
}

return {renderVariation};},
"visual/scenes.mjs":()=>{
const {palette,rect,path,block,group,at,move,opacity,frames,star,keyboardBase,work,flood,splash,trophy,keycap,victoryBackground}=load("visual/base.mjs");
// One primary verb + silhouette per slot. Reusing a face is intentional;
// reusing a whole keyboard scene with different particle counts is not.
const sceneSpecs={
  happy:[
    ["conveyor","Cheerful conveyor","Hop little parcels into the inbox",5],
    ["piano","Work-song piano","Play the keys like a tiny piano",4],
    ["paper-plane","Paper-plane post","Fold a page, then send it sailing",5],
    ["block-tower","Happy little builder","Stack bright cubes into a tower",5],
    ["stamp","Stamp-dance","Bounce a giant stamp onto a card",4]
  ],
  excited:[
    ["turbo","Turbo keyboard","Pound the keys in a frantic flurry",1.6],
    ["juggle","Too many ideas","Juggle three work cubes overhead",3],
    ["rocket","Keyboard liftoff","A rocket keyboard lifts on square flames",4],
    ["treadmill","Task treadmill","Cards race past on a roller belt",3.6],
    ["pinball","Pinball brain","A bright cube ricochets among bumpers",3]
  ],
  proud:[
    ["pedestal","The grand workstation","A desk rises on a show-off pedestal",5],
    ["conductor","Maestro of the tabs","A baton conducts an orbit of cards",4],
    ["origami","Effortless origami","Fold a plain sheet into a pixel crane",5],
    ["polish","Polish the masterpiece","Buff one work tile to a ridiculous shine",4.5],
    ["one-key","One-key virtuoso","Perform an absurd flourish on one giant key",4]
  ],
  curious:[
    ["magnifier","Under the lens","A giant lens inspects a little specimen",5],
    ["periscope","What is over there?","Extend a periscope, then pivot its eye",5],
    ["explode","How does this work?","Pull a cube apart and rebuild it",5],
    ["maze","Follow the maze","Chase a wandering square through a maze",5],
    ["box","Mystery-box inspection","Lift the lid and peer into the box",5]
  ],
  determined:[
    ["steady","Steady typing","A planted, deliberate keyboard rhythm",2.4],
    ["uphill","One more push","Shove a heavy cube up stepped ground",5],
    ["brick-wall","Brick by brick","Build a wall one block at a time",5],
    ["winch","Haul the workload","Crank a pulley to lift a heavy stack",5],
    ["scissors","Cut through the tangle","Giant scissors snip a knotted strip",4]
  ],
  grumpy:[
    ["key-rain","Keyboard meltdown","Spray keycaps in every direction",1.8],
    ["snap","Bash, bash, SNAP!","Three accelerating desk slams → snap → scatter",3.2],
    ["throw","Smash the fourth wall","Desk hit → three screen hits → cracks → throw",4.4],
    ["crumple","Paper rage, rapid-fire","Crumple and fling three pages: right, left, right",2.7],
    ["boiler","Pressure cooker","Frantic lid rattle → two steam bursts → lid launch",2.4]
  ],
  sad:[
    ["flood","Typing through a flood","Cube tears submerge the keyboard",3.2],
    ["buckets","Bucket brigade","Catch the tears; the buckets overflow",5],
    ["tissue","Never-ending tissue","A printer dispenses an accordion of tissue",5],
    ["umbrella","Rainy-day workstation","Shelter the work under a little umbrella",5],
    ["raft","Keep the work afloat","A work raft bobs on a sea of blue cubes",5]
  ]
};
const activeNames={
  needs_you:["Knock-knock request","Raise the little flag","Ring for attention"],
  task_complete:["Trophy fireworks","Curtain-call reveal","Onto the podium"],
  listening:["Focused attention","Headphones on","The listening trumpet"]
};
const activeCaptions={
  needs_you:["Knock on the door, then wait","Unfurl an amber request flag","One little bell gesture, then stillness"],
  task_complete:["Cup entrance + a square-confetti fountain","Curtains open onto the result","A stepped podium rises under the cup"],
  listening:["Four large focus corners frame the face","A pixel headset settles around the face","Lean toward a comically large ear trumpet"]
};
const ink=palette.ink,gray=palette.dim,light=palette.prop,blue=palette.blue,coral=palette.cheek,amber=palette.amber;
const square=(x,y,s,c=ink)=>rect(x,y,s,s,c);
function story(ctx,drawings,seconds,part,once=false,still=2){
  if(!ctx.motion)return group(drawings[Math.min(still,drawings.length-1)],`data-part="${part}"`);
  if(!once)return frames(ctx,drawings,seconds,part);
  if(ctx.loopSeconds){
    const duration=ctx.loopSeconds,returning=["flag-request","podium-rise"].includes(part);
    const beats=drawings.map((_,i)=>[i*seconds/(drawings.length-1),i]);
    if(returning)for(let i=drawings.length-2;i>=0;i--)beats.push([duration-.6+(drawings.length-2-i)*.12,i]);
    else beats.push([duration-.15,0]);
    beats.push([duration,0]);
    return timedStory(ctx,drawings,duration,part,beats.map(b=>b[0]/duration),beats.map(b=>b[1]),still);
  }
  const times=drawings.map((_,i)=>i/(drawings.length-1)).join(";");
  return group(drawings.map((drawing,i)=>group(opacity(ctx,drawings.map((_,j)=>Number(j===i)).join(";"),seconds,times,"1")+drawing,`opacity="${i===0?1:0}" data-frame="${i}"`)).join(""),`data-part="${part}"`);
}
// Anticipation, fast impact/travel, aftermath, reset. The frames stay integer
// aligned; the joke no longer moves at the same speed through all five poses.
function timedStory(ctx,drawings,seconds,part,times,order,still=2){
  if(!ctx.motion)return group(drawings[still],`data-part="${part}"`);
  return group(drawings.map((drawing,i)=>group(opacity(ctx,order.map(j=>Number(j===i)).join(";"),seconds,times.join(";"))+drawing,`opacity="${i===order[0]?1:0}" data-frame="${i}"`)).join(""),`data-part="${part}"`);
}
function miniBoard(x,y,w=154,columns=10,vertical=false){
  let a=rect(0,0,w,28,gray)+rect(3,3,w-6,21,palette.black);
  const cell=Math.floor((w-10)/columns);
  for(let r=0;r<2;r++)for(let c=0;c<columns;c++)a+=rect(6+c*cell,6+r*8,cell-4,5,light);
  a+=rect(Math.floor(w*.3),24,Math.floor(w*.4),3,light);
  return at(x,y,vertical?group(a,'transform="rotate(90)"'):a);
}
function card(x,y,w=26,h=30,c=light){return at(x,y,rect(0,0,w,h,c)+rect(4,5,w-8,3,gray)+rect(4,12,w-12,3,gray)+rect(4,19,7,4,gray));}
function cube(x,y,s=18,c=blue){return at(x,y,square(0,0,s,c)+rect(2,2,s-4,3,ink)+rect(s-4,5,3,s-7,gray));}
function burst(x,y,phase=1,c=amber){return [[-1,0],[1,0],[0,-1],[0,1],[-1,-1],[1,-1]].map(([dx,dy],i)=>square(x+dx*(8+phase*5),y+dy*(5+phase*4),i%2?3:4,c)).join("");}
function wheel(x,y,r=10,phase=0){return at(x,y,rect(-r,-r,2*r,2*r,gray)+rect(-r+3,-r+3,2*r-6,2*r-6,palette.black)+(phase%2?rect(-r+3,-2,2*r-6,4,light):rect(-2,-r+3,4,2*r-6,light)));}
function note(x,y,c=coral){return at(x,y,rect(6,0,3,15,c)+rect(9,0,7,4,c)+rect(0,12,6,6,c));}
function pixelRod(x,y,tilt,steps=7,c=light){return Array.from({length:steps},(_,i)=>square(x+tilt*i*4,y+i*4,5,c)).join("");}
function flame(x,y,p){return at(x,y,rect(0,0,8,10+p*4,amber)+rect(2,0,4,7+p*3,coral)+square(1,14+p*4,4,amber));}
function splitBoard(x,y,left=true){
  let a=miniBoard(0,0,69,4);
  a+=path(left?"M69 0h7v6h-5v6h6v6h-7v10h-1Z":"M0 0h-7v6h5v6h-6v6h7v10h1Z",light);
  return at(x,y,a);
}
function plane(x,y,size=1){return at(x,y,group(path("M0 12h12V8h12V4h16V0h12v4H40v4H28v4H16v4H8v8H4v-8H0Z",ink)+path("M16 12h24v4H28v4h-8v4h-4Z",blue),`transform="scale(${size})"`));}
function boat(x,y){return at(x,y,path("M0 0h80v5h-6v6h-6v6H12v-6H6V5H0Z",light)+rect(15,3,50,4,ink));}
function steam(x,y,p){return [0,1,2].map(i=>square(x+(i%2?7:-2),y-i*10-p*4,5-i,light)).join("");}

// Seconds, pose, face recoil. Irregularly spaced acting beats, not a speed
// multiplier on V2's five-pose loops. Large impacts do not flash the screen.
const grumpyTiming={
  snap:{seconds:3.2,still:"apart",hits:[.38,.68,.94],steps:[
    [0,"ready",0,0],[.24,"lift",0,-4],[.38,"slam1",-2,5],[.48,"recoil",2,-3],
    [.68,"slam2",3,5],[.77,"lift",-2,-5],[.94,"slam3",-3,6],[1.05,"strain",0,3],
    [1.2,"crack",0,-4],[1.3,"split",-2,-1],[1.42,"apart",2,1],[1.56,"fly",0,-2],
    [1.86,"fallen",0,2],[1.98,"fall-away",0,1],[2.08,"gone",0,0],[2.16,"feed",0,0],[2.28,"reload",0,1],[2.38,"ready",0,0],[2.44,"tap",0,3],
    [2.58,"ready",0,0],[2.78,"tap",0,2],[2.9,"ready",0,0]
  ]},
  throw:{seconds:4.4,still:"screen3",hits:[.32,.68,1.05,1.48],steps:[
    [0,"ready",0,0],[.18,"lift",0,-5],[.32,"desk",-3,5],[.43,"recoil0",2,-4],
    [.56,"rush0",0,-2],[.68,"screen1",-4,6],[.78,"recoil1",3,-4],
    [.94,"rush1",0,-2],[1.05,"screen2",4,5],[1.16,"recoil2",-3,-5],
    [1.36,"rush2",0,-3],[1.48,"screen3",-4,7],[1.6,"recoil3",3,-3],
    [1.8,"windup",-6,2],[1.96,"release",5,-3],[2.08,"tumble",3,0],
    [2.22,"exit",1,0],[2.36,"empty",0,0],[2.62,"glare",-3,0],
    [2.92,"wipe1",2,0],[3.06,"wipe2",-1,0],[3.2,"clear",0,0],
    [3.26,"feed",0,0],[3.34,"reload",0,2],[3.42,"ready",0,0],[3.48,"tap",0,3],[3.6,"ready",0,-1],
    [3.78,"tap",0,3],[3.91,"ready",0,-2],[4.08,"tap",0,2],[4.2,"ready",0,0]
  ]},
  crumple:{seconds:2.7,still:"ball2",hits:[.31,1.04,1.77],steps:[
    [0,"page0",0,0],[.12,"scrunch0",-3,3],[.23,"squeeze0",3,0],[.31,"ball0",-2,4],
    [.41,"toss0",5,-3],[.51,"flight0",3,0],[.62,"edge0",0,0],
    [.73,"page1",0,1],[.84,"scrunch1",3,3],[.94,"squeeze1",-3,0],[1.04,"ball1",2,4],
    [1.14,"toss1",-5,-3],[1.25,"flight1",-3,0],[1.36,"edge1",0,0],
    [1.46,"page2",0,1],[1.57,"scrunch2",-4,3],[1.67,"squeeze2",4,0],[1.77,"ball2",-2,4],
    [1.87,"toss2",6,-4],[1.98,"flight2",3,0],[2.08,"edge2",0,0],
    [2.2,"pile",0,2],[2.28,"clear1",0,1],[2.36,"clear2",0,0],[2.4,"feed",0,0],[2.48,"reload",0,-1],[2.56,"page0",0,0]
  ]},
  boiler:{seconds:2.4,still:"launch",hits:[.49,.91,1.34],steps:[
    [0,"rest",0,0],[.16,"left",-2,1],[.25,"right",2,-1],[.33,"left",-3,1],
    [.41,"right",3,-1],[.49,"puff1",0,-3],[.6,"left",-2,2],[.69,"right",2,-1],
    [.77,"left",-3,2],[.84,"right",3,-2],[.91,"puff2",0,-4],[1.04,"left",-3,2],
    [1.13,"right",3,-2],[1.22,"squat",0,4],[1.34,"launch",0,-6],[1.45,"high",0,-3],
    [1.61,"fall",0,0],[1.78,"land",-2,3],[1.9,"bounce",2,-2],[2.05,"settle",0,1],[2.2,"rest",0,0]
  ]}
};
function grumpyActing(ctx){
  const id=sceneSpecs.grumpy[ctx.variant-1][0],plan=grumpyTiming[id];
  if(!plan)return null;
  const steps=[...plan.steps,[plan.seconds,plan.steps[0][1],...plan.steps[0].slice(2)]];
  return move(ctx,steps.map(s=>`${s[2]} ${s[3]}`).join(";"),plan.seconds,steps.map(s=>s[0]/plan.seconds).join(";"));
}
function beatScene(ctx,id,draw){
  const plan=grumpyTiming[id];
  if(!ctx.motion)return group(draw(plan.still),`data-part="story-${id}" data-cycle-seconds="${plan.seconds}"`);
  const poses=[...new Set(plan.steps.map(s=>s[1]))];
  const end=[plan.seconds,plan.steps[0][1]];
  const steps=[...plan.steps,end],times=steps.map(s=>s[0]/plan.seconds).join(";");
  return group(poses.map((pose,i)=>group(opacity(ctx,steps.map(s=>Number(s[1]===pose)).join(";"),plan.seconds,times)+draw(pose),`opacity="${i===0?1:0}" data-pose="${pose}"`)).join(""),`data-part="story-${id}" data-cycle-seconds="${plan.seconds}"`);
}
function deskLine(){return rect(46,218,228,5,gray)+rect(58,223,7,10,gray)+rect(257,223,7,10,gray);}
function hitSquares(level=1){return burst(85,205,level,amber)+burst(235,205,level,amber);}
function crumpled(x,y,s=30){return at(x,y,path(`M5 0h${s-10}v5h5v${s-10}h-5v5H5v-5H0V5h5Z`,light)+rect(7,8,Math.max(2,s-14),3,gray)+rect(Math.min(12,s-5),Math.min(12,s-5),3,Math.max(2,s-17),gray));}
function frontBoard(x,y,w,h){
  let a=rect(x,y,w,h,light)+rect(x+4,y+4,w-8,h-8,gray);
  const cw=Math.floor((w-16)/10),rh=Math.floor((h-16)/2);
  for(let r=0;r<2;r++)for(let c=0;c<10;c++)a+=rect(x+9+c*cw,y+7+r*(rh+3),cw-4,rh,palette.black);
  return a;
}
function glassCracks(level=1){
  // Stair-step orthogonal cracks: square-pixel glass, not smooth vector lines.
  const lines=[
    [[158,178],[158,162],[143,162],[143,148],[128,148],[128,127],[118,127]],
    [[164,174],[180,174],[180,161],[200,161],[200,150],[225,150],[225,141],[258,141]],
    [[158,188],[149,188],[149,200],[127,200],[127,211],[107,211],[107,227]],
    [[174,185],[190,185],[190,197],[214,197],[214,209],[246,209],[246,221],[284,221]],
    [[143,148],[133,148],[133,115],[145,115],[145,94],[131,94],[131,68],[120,68],[120,41]],
    [[128,148],[99,148],[99,155],[68,155],[68,146],[34,146],[34,132],[12,132]],
    [[200,161],[217,161],[217,150],[254,150],[254,135],[284,135],[284,118],[309,118]],
    [[145,94],[159,94],[159,72],[173,72],[173,53],[165,53],[165,27]]
  ];
  const count=[0,2,4,8][level];
  return group(lines.slice(0,count).map(points=>points.slice(1).map(([x,y],i)=>{
    const [px,py]=points[i];return rect(Math.min(px,x),Math.min(py,y),Math.max(3,Math.abs(x-px)+3),Math.max(3,Math.abs(y-py)+3),light);
  }).join("")).join(""),'data-part="screen-cracks" opacity="0.68"');
}
function grumpyActionScene(ctx,id){
  return beatScene(ctx,id,pose=>{
    if(id==="snap"){
      let p=deskLine();
      if(["ready","tap","lift","recoil","slam1","slam2","slam3","strain"].includes(pose)){
        const y=({ready:185,tap:190,lift:163,recoil:167,slam1:190,slam2:190,slam3:190,strain:181})[pose];
        p+=miniBoard(83+(pose==="slam2"?4:pose==="slam3"?-4:0),y);
        if(pose.startsWith("slam"))p+=hitSquares(Number(pose.at(-1)));
        if(["slam3","strain"].includes(pose))p+=path("M158 181h5v9h-4v8h5v10h-6v-11h3v-7h-3Z",coral);
      }else if(pose==="reload"||pose==="feed")p+=miniBoard(83,pose==="feed"?233:205);
      else if(!["empty","gone"].includes(pose)){
        const [d,y]=({crack:[5,182],split:[20,176],apart:[36,176],fly:[56,185],fallen:[64,206],"fall-away":[68,228]})[pose];
        p+=group(splitBoard(83-d,y,true),'data-part="broken-left"')+group(splitBoard(168+d,y+3,false),'data-part="broken-right"');
        if(pose==="crack"||pose==="split")p+=burst(158,188,3,amber)+path("M154 177h5v10h7v11h-5v-7h-7Z",coral);
      }
      return p;
    }
    if(id==="throw"){
      let p=deskLine(),cracks=0;
      if(["ready","tap","lift","desk","recoil0","rush0","reload","feed"].includes(pose)){
        if(pose==="rush0")p+=frontBoard(60,168,200,39);
        else p+=miniBoard(83,({ready:185,tap:190,lift:163,desk:190,recoil0:163,reload:204,feed:233})[pose]);
        if(pose==="desk")p+=hitSquares(2);
      }else if(pose.startsWith("screen")){
        cracks=Number(pose.at(-1));p+=frontBoard(35,154,250,54)+burst(39,168,2,amber)+burst(278,168,2,amber);
      }else if(pose.startsWith("rush")){
        cracks=Number(pose.at(-1));p+=frontBoard(60,168,200,39);
      }else if(pose.startsWith("recoil")){
        cracks=Number(pose.at(-1));p+=miniBoard(90,176);
      }else {
        cracks=["clear","reload","ready","tap"].includes(pose)?0:pose==="wipe2"?1:pose==="wipe1"?2:3;
        if(pose==="windup")p+=miniBoard(37,174);
        if(pose==="release")p+=miniBoard(148,161)+rect(114,190,23,4,light)+rect(97,199,14,3,gray);
        if(pose==="tumble")p+=miniBoard(308,63,154,10,true)+rect(245,193,21,4,light);
        if(pose==="exit")p+=square(302,163,5,gray)+square(288,179,4,gray);
        if(pose==="wipe1"||pose==="wipe2")p+=rect(pose==="wipe1"?113:219,176,32,18,coral);
      }
      return p+(cracks?glassCracks(cracks):"");
    }
    if(id==="crumple"){
      const match=pose.match(/^(page|scrunch|squeeze|ball|toss|flight|edge)([012])$/);
      const cycle=match?Number(match[2]):pose==="reload"?0:2,step=match?.[1]||pose;
      let p=rect(115,223,90,4,gray);
      const clearing=pose==="clear1"?10:pose==="clear2"?27:0;
      const fresh=["reload","feed"].includes(pose);
      if(!fresh&&(cycle>=1||pose==="pile"))p+=crumpled(286,215+clearing,19);
      if(!fresh&&(cycle>=2||pose==="pile"))p+=crumpled(13,216+clearing,18);
      if(pose==="pile"||clearing)p+=crumpled(268,220+clearing,15);
      if(step==="page"||fresh)p+=card(121,pose==="feed"?235:pose==="reload"?191:161,78,59,ink);
      if(step==="scrunch")p+=path("M126 172h60v6h12v34h-12v8h-51v-7h-13v-31h4Z",ink)+rect(142,180,4,29,gray)+rect(152,187,24,4,gray);
      if(step==="squeeze")p+=crumpled(138,178,44)+burst(159,195,1,light);
      if(step==="ball")p+=crumpled(145,192,30);
      const right=cycle%2===0;
      if(step==="toss")p+=crumpled(right?200:84,167,28)+rect(right?173:118,191,19,3,gray);
      if(step==="flight")p+=crumpled(right?259:35,162,23)+rect(right?239:64,185,14,3,light);
      if(step==="edge")p+=crumpled(right?295:7,197,18)+square(right?287:29,181,4,gray);
      return p;
    }
    const dx=pose==="left"?-4:pose==="right"?4:0;
    const lid=({rest:0,left:-2,right:-4,puff1:-13,puff2:-22,squat:2,launch:-39,high:-52,fall:-25,land:1,bounce:-12,settle:-2})[pose];
    let p=at(dx,0,rect(113,187,94,37,gray)+rect(120,193,80,25,blue)+rect(104,203,9,11,gray)+rect(207,203,9,11,gray)+rect(135,208,48,5,coral));
    p+=rect(107-dx,179+lid,106,9,light)+rect(148-dx,172+lid,24,7,gray);
    const power=["launch","high"].includes(pose)?3:pose==="puff2"?2:1;
    p+=steam(224+dx,194,power)+steam(90-dx,198,power+1);
    if(["puff1","puff2","launch","high"].includes(pose))for(let i=0;i<power+2;i++)p+=square(105-i*9,173-i*4,6,light)+square(210+i*9,173-i*4,6,light);
    if(pose==="land")p+=hitSquares(1);
    return p;
  });
}

// Keep the main gag; give each one-way action a forward recovery instead of
// rewinding the destruction or replacing its prop in full view.
function closedWorkStory(ctx,id,shots,seconds){
  let drawings=[...shots],order,times;
  const backtrack=["piano","polish","maze","winch","conductor","magnifier"];
  if(backtrack.includes(id)){
    order=[0,1,2,3,4,3,2,1,0,0];times=[0,.14,.28,.42,.56,.66,.76,.86,.94,1];
  }else if(["conveyor","treadmill","juggle"].includes(id)){
    drawings=[];
    for(let f=0;f<=30;f++){
      let p="";
      if(id==="conveyor"){
        p=rect(55,199,170,12,gray)+rect(58,202,164,5,palette.black)+wheel(68,215,7,f)+wheel(208,215,7,f)+path("M231 185h8v23h39v-23h8v31h-55Z",amber);
        for(let i=0;i<4;i++)p+=cube(65+((i*40+f*5)%150),180,16,i%2?blue:coral);
      }else if(id==="treadmill"){
        p=wheel(76,208,15,f)+wheel(244,208,15,f)+rect(77,190,168,5,light)+rect(77,221,168,5,gray)+rect(51,206,11,4,coral)+rect(258,206,11,4,coral);
        for(let i=0;i<4;i++)p+=card(81+((i*36+Math.round(f*134/30))%134),166,22,25,i%2?blue:ink);
      }else{
        p=path("M81 217h5v5h147v-5h5v10H81Z",gray);
        const pos=[[90,183],[131,161],[189,173],[215,204],[133,209]],phase=f/6;
        for(let i=0;i<3;i++){
          const j=Math.floor(phase+i*2)%5,k=(j+1)%5,t=phase%1;
          p+=cube(Math.round(pos[j][0]+(pos[k][0]-pos[j][0])*t),Math.round(pos[j][1]+(pos[k][1]-pos[j][1])*t),20,[blue,coral,amber][i]);
        }
      }
      drawings.push(p);
    }
    order=drawings.map((_,i)=>i);times=order.map(i=>i/30);order.push(0);times.push(1);
    // No duplicate 1.0 key time: the final drawing already equals the first.
    order.pop();times.pop();
  }else if(id==="paper-plane"){
    const stack=card(73,204,34,22,light)+rect(70,228,55,3,gray);
    drawings.push(stack+plane(302,141),stack+plane(336,136),stack+card(127,234,54,42,ink),stack+card(127,206,54,42,ink),stack+card(127,181,54,42,ink),shots[0]);
  }else if(["block-tower","brick-wall","origami"].includes(id)){
    const support=id==="block-tower"?rect(95,223,130,5,gray):id==="brick-wall"?rect(99,222,130,6,gray):"";
    const final=shots[4].replace(support,""),first=shots[0].replace(support,"");
    drawings.push(...[25,85,185,325].map(dx=>support+at(dx,0,final)),support+at(-310,0,first),support+at(-145,0,first),support+at(-45,0,first),shots[0]);
  }else if(id==="stamp"){
    const press=rect(117,176,86,10,amber)+rect(145,164,30,13,gray);
    drawings.push(...[45,125,230].map(dx=>press+card(109+dx,201,103,23,ink)+star(157+dx,204,16,coral)),press+card(-91,201,103,23,ink),press+card(25,201,103,23,ink),shots[0]);
  }else if(id==="uphill"){
    const ramp=path("M70 224h30v-10h30v-10h30v-10h30v-10h30v-10h30v54H70Z",gray);
    drawings.push(ramp+cube(223,137,27,blue),ramp+cube(271,142,27,blue),ramp+cube(322,161,27,blue),ramp+cube(-26,187,27,blue),ramp+cube(27,187,27,blue),ramp+cube(65,187,27,blue),shots[0]);
  }else if(id==="tissue"){
    const printer=rect(100,192,121,34,gray)+rect(107,198,107,18,palette.black)+rect(175,207,12,5,blue)+rect(117,188,59,10,ink);
    const tissue=shots[4].replace(printer,"");
    drawings.push(...[-20,-70,-150,-205].map(dx=>printer+at(dx,-6,tissue)),printer+rect(124,184,38,6,ink),printer+rect(124,184,38,6,ink)+rect(132,177,38,6,light),shots[0]);
  }else if(id==="buckets"){
    for(let f=3;f>=0;f--){
      let p=card(133,193,52,31,ink);
      for(const x of[61,213]){
        p+=rect(x,179,37,45,gray)+rect(x+4,183,29,37,palette.black)+rect(x+5,213-f*5,27,5+f*5,blue)+rect(x+7,169,23,4,light)+rect(x+4,172,4,9,light)+rect(x+29,172,4,9,light);
        p+=square(x+30,222,4,blue)+square(x+36,228+(3-f),3,palette.lightWater);
      }
      drawings.push(p);
    }
    drawings.push(shots[0]);
  }else drawings.push(shots[0]);
  if(!order){
    // Keep the forward performance in the first 70%; dedicate the tail to
    // visible delivery/cleanup/replenishment. The next loop starts at rest.
    order=drawings.map((_,i)=>i);
    times=drawings.map((_,i)=>i<5?i*.14:.66+(i-4)*(.28/(drawings.length-5)));
    order.push(0);times.push(1);
  }
  return timedStory(ctx,drawings,seconds,"story-"+id,times,order);
}

function drawWorkScene(ctx){
  const [id,,,seconds]=sceneSpecs[ctx.mood][ctx.variant-1];
  let a="",shots=[];
  if(id==="key-rain")a=work(ctx);
  else if(ctx.mood==="grumpy"&&grumpyTiming[id])a=grumpyActionScene(ctx,id);
  else if(id==="flood")a=keyboardBase(ctx)+flood(ctx);
  else if(id==="turbo")a=work(ctx);
  else if(id==="steady")a=keyboardBase(ctx)+rect(74,168,4,33,blue)+rect(243,168,4,33,blue);
  else {
    for(let f=0;f<5;f++){
      let p="";
      switch(id){
        case"conveyor":
          p=rect(55,199,170,12,gray)+rect(58,202,164,5,palette.black)+wheel(68,215,7,f)+wheel(208,215,7,f)+path("M231 185h8v23h39v-23h8v31h-55Z",amber);
          for(let i=0;i<4;i++){const x=65+((i*40+f*14)%150);p+=cube(x,180-(i===f%4?7:0),16,i%2?blue:coral);}break;
        case"piano":
          p=rect(77,181,166,34,gray)+rect(82,185,156,25,ink)+rect(90,215,8,12,gray)+rect(222,215,8,12,gray);
          for(let i=0;i<11;i++){p+=rect(84+i*14,186,2,23,palette.black);if(i%3!==2)p+=rect(91+i*14,185,6,14,palette.black);}
          p+=rect(84+(f*2%10)*14,202,11,7,coral)+note(42,176-f*5)+note(263,178-((f+2)%5)*5);break;
        case"paper-plane":
          p=card(73,204,34,22,light)+rect(70,228,55,3,gray);
          if(f===0)p+=card(127,170,54,42,ink);
          else if(f===1)p+=path("M132 178h46v6h-8v8h-10v12h-28Z",ink)+rect(141,184,24,3,blue);
          else p+=plane([0,0,132,207,263][f],[0,0,180,162,147][f]);break;
        case"block-tower":
          p=rect(95,223,130,5,gray);
          for(let i=0;i<=f;i++)p+=cube(139+(i%2?3:-3),204-i*11,18,[blue,amber,coral][i%3]);
          p+=cube(204-f*6,196-f*5,16,coral);break;
        case"stamp":{
          const y=[164,170,187,168,164][f];p=card(109,201,103,23,ink)+rect(117,y+12,86,10,amber)+rect(145,y,30,13,gray);
          if(f>=2)p+=star(157,204,16,coral);if(f===2)p+=burst(160,196,2,amber);break;}
        case"juggle":{
          const positions=[[90,183],[131,161],[189,173],[215,204],[133,209]];p=path("M81 217h5v5h147v-5h5v10H81Z",gray);
          for(let i=0;i<3;i++){const [x,y]=positions[(f+i*2)%5];p+=cube(x,y,20,[blue,coral,amber][i]);}break;}
        case"rocket":{
          const y=[189,180,161,168,186][f];p=miniBoard(98,y,124,8)+flame(118,y+27,f%3)+flame(193,y+27,(f+1)%3)+rect(92,y+10,6,19,coral)+rect(222,y+10,6,19,coral);break;}
        case"treadmill":
          p=wheel(76,208,15,f)+wheel(244,208,15,f)+rect(77,190,168,5,light)+rect(77,221,168,5,gray);
          for(let i=0;i<4;i++)p+=card(81+((i*36+f*19)%134),166,22,25,i%2?blue:ink);
          p+=rect(51,206,11,4,coral)+rect(258,206,11,4,coral);break;
        case"pinball":{
          p=rect(89,161,142,65,gray)+rect(93,165,134,57,palette.black)+square(112,177,11,coral)+square(189,177,11,blue)+square(153,196,11,amber);
          const pos=[[99,207],[142,172],[207,204],[175,180],[123,211]][f];p+=square(...pos,7,ink)+rect(106,216,29,3,light)+rect(186,216,29,3,light);break;}
        case"pedestal":{
          const lift=[0,5,13,13,5][f];p=rect(112,222-lift,96,8,gray)+rect(137,206-lift,46,17,light)+miniBoard(91,179-lift,138,9)+rect(93,225,134,5,amber);
          if(f>=2)p+=star(62,177,16,amber)+star(253,177,16,amber);break;}
        case"conductor":
          p=rect(115,218,90,6,gray)+rect(158,195,5,24,gray);
          for(let i=0;i<3;i++)p+=card(73+i*72,171+((f+i)%3)*10,27,30,[blue,ink,amber][i]);
          p+=pixelRod(155,166,[-1,-1,0,1,0][f],7,ink);break;
        case"origami":
          if(f===0)p=card(122,172,77,52,ink);
          else if(f===1)p=path("M112 214h23v-12h23v-12h23v-12h23v46h-92Z",ink);
          else p=path("M86 185h22v8h20v8h20v-18h8v-18h8v-8h19v6h-13v31h-8v10h31v-10h18v-10h23v9h-18v12h-20v12h-31v10h-12v-11h-29v-11h-24v-10H86Z",ink)+square(172,159,3,palette.black)+rect(148,216,7,13,blue);break;
        case"polish":
          p=rect(119,169,82,51,amber)+rect(125,175,70,39,blue)+rect(133,182,25,3,ink)+rect(133,190,46,3,ink)+rect(107+f*14,198-f%2*9,28,13,coral);
          if(f>=3)p+=star(182,158,24,ink)+star(105,207,16,ink);break;
        case"one-key":{
          const d=f===2?9:0;p=rect(111,216,98,8,gray)+at(131,166+d,keycap(48,"E"))+rect(101,221,118,5,amber);
          if(f===2)p+=burst(157,196,5,amber);break;}
        case"magnifier":{
          const x=111+[-10,0,10,0,-10][f];p=card(139,190,28,31,blue)+at(x,157,path("M10 0h39v9h9v34h-9v9H10v-9H0V9h10Zm4 10v32h30V10Z",light)+rect(47,44,10,10,gray)+rect(55,52,10,10,gray))+square(x+22,177,7,blue);break;}
        case"periscope":{
          const h=[33,43,53,53,43][f];p=rect(115,216,104,9,gray)+rect(164,212-h,18,h,blue)+rect(125,212-h,57,18,blue)+rect(119,209-h,12,24,light)+rect(120,215-h,8,12,palette.black)+square(121,217-h+f%2*3,5,ink)+rect(158,199,28,5,light);break;}
        case"explode":{
          const spread=[0,10,22,13,0][f];p=rect(104,223,112,4,gray);
          for(let i=0;i<4;i++)p+=cube(138+(i%2)*23+(i%2?spread:-spread),180+Math.floor(i/2)*23+(i<2?-spread:0),20,[blue,amber,coral,light][i]);break;}
        case"maze":{
          p=rect(85,161,150,67,gray)+rect(90,166,140,57,palette.black)+rect(112,166,5,35,blue)+rect(138,188,5,35,blue)+rect(164,166,5,35,blue)+rect(190,188,5,35,blue)+rect(116,196,17,5,blue);
          const pos=[[96,171],[98,210],[146,208],[173,174],[213,210]][f];p+=square(...pos,7,ink);break;}
        case"box":{
          const lift=[0,9,22,22,9][f];p=rect(114,190,92,36,amber)+rect(122,196,76,24,palette.black)+rect(110,182-lift,100,10,light)+rect(151,186-lift,18,5,gray);
          if(f>=2)p+=cube(149,173,15,blue)+square(136,185,4,coral)+square(184,178,4,ink);break;}
        case"uphill":{
          p=path("M70 224h30v-10h30v-10h30v-10h30v-10h30v-10h30v54H70Z",gray);
          p+=cube(83+f*28,187-f*10,27,blue)+burst(69+f*28,221-f*10,0,light);break;}
        case"brick-wall":
          p=rect(99,222,130,6,gray);for(let i=0;i<3+f*2;i++)p+=rect(104+(i%4)*29+(Math.floor(i/4)%2?8:0),204-Math.floor(i/4)*17,25,13,[blue,light,amber][Math.floor(i/4)%3]);break;
        case"winch":{
          const lift=[0,8,17,26,17][f];p=rect(85,158,8,70,gray)+rect(85,158,133,8,gray)+wheel(203,174,11,f)+rect(202,184,3,33-lift,light)+card(176,211-lift,57,15,blue)+card(179,202-lift,51,12,ink)+wheel(84,198,17,f)+rect(51,223,70,5,gray);break;}
        case"scissors":{
          p=rect(83,199,154,8,blue)+square(117,193,19,blue)+square(187,193,19,blue);
          const open=[true,true,false,false,true][f];p+=square(open?128:143,166,19,coral)+square(open?133:148,171,9,palette.black)+square(open?173:164,166,19,coral)+square(open?178:169,171,9,palette.black)+pixelRod(open?144:153,184,open?1:0,8)+pixelRod(open?173:164,184,open?-1:0,8);
          if(!open)p+=rect(153,201,15,10,palette.black)+burst(160,203,2,blue);break;}
        case"snap":
          if(f<2)p=miniBoard(83,183+(f?4:0))+ (f?path("M158 181h5v9h-4v8h5v10h-6v-11h3v-7h-3Z",coral):"");
          else {const d=f===2?29:f===3?52:13;p=splitBoard(83-d,182+(f===3?14:0),true)+splitBoard(168+d,188+(f===3?17:0),false);if(f===2)p+=burst(161,193,3,amber)+path("M151 185h4v7h7v7h7v5h-11v-6h-7Z",coral);}break;
        case"throw":
          if(f===0)p=miniBoard(83,185);
          if(f===1)p=miniBoard(105,165);
          if(f===2)p=miniBoard(296,71,154,10,true)+square(247,211,5,gray)+square(256,205,4,gray);
          if(f===3)p=square(302,155,5,gray)+square(291,169,4,gray)+square(283,183,3,gray);
          if(f===4)p=miniBoard(83,210);break;
        case"crumple":
          if(f===0)p=card(120,166,80,60,ink);
          if(f===1)p=path("M130 174h54v8h10v31h-8v9h-51v-8h-9v-31h4Z",ink)+rect(142,182,4,30,gray)+rect(152,188,24,4,gray);
          if(f===2)p=at(144,191,path("M5 0h24v5h6v24h-6v6H5v-5H0V5h5Z",light)+rect(8,8,19,4,gray)+rect(14,14,4,16,gray));
          if(f===3)p=cube(252,162,25,light)+square(232,189,5,gray)+square(219,198,3,gray);
          if(f===4)p=card(124,204,70,23,ink);break;
        case"boiler":{
          const dy=[0,-2,-15,-25,-7][f];p=rect(113,187,94,37,gray)+rect(120,193,80,25,blue)+rect(107,179+dy,106,9,light)+rect(148,172+dy,24,7,gray)+rect(104,203,9,11,gray)+rect(207,203,9,11,gray)+rect(135,208,48,5,coral)+steam(224,194,f)+steam(92,202,(f+2)%5);break;}
        case"buckets":
          for(const [i,x]of[61,213].entries()){p+=path(`M${x} 179h37v45H${x}Z`,gray)+rect(x+4,183,29,37,palette.black)+rect(x+5,213-f*5,27,5+f*5,blue)+rect(x+7,169,23,4,light)+rect(x+4,172,4,9,light)+rect(x+29,172,4,9,light);if(f>2)p+=burst(x+17,190,1,palette.lightWater);}
          p+=card(133,193,52,31,ink);break;
        case"tissue":
          p=rect(100,192,121,34,gray)+rect(107,198,107,18,palette.black)+rect(175,207,12,5,blue)+rect(117,188,59,10,ink);
          for(let i=0;i<3+f;i++)p+=rect(124+(i%2?8:0),184-i*7,38,6,i%2?light:ink);break;
        case"umbrella":
          p=miniBoard(102,198,118,8)+path("M90 179v-6h12v-6h18v-6h20v-6h40v6h20v6h18v6h12v6Z",blue)+rect(158,176,4,29,light)+rect(150,202,8,4,light)+burst(85,187,f%2,palette.lightWater)+burst(236,187,(f+1)%2,palette.lightWater);break;
        case"raft":{
          const dy=[0,-3,1,4,0][f];for(let i=0;i<17;i++)p+=square(56+i*12,221+((i+f)%3)*4,7,[blue,palette.water,palette.lightWater][i%3]);
          p+=boat(121,203+dy)+miniBoard(124,179+dy,74,5)+rect(208,170+dy,4,43,light)+path(`M212 ${171+dy}h23v5h-5v7h-18Z`,ink);break;}
      }
      shots.push(p);
    }
    a=closedWorkStory(ctx,id,shots,seconds);
  }
  const active=group(opacity(ctx,"1;0;1;1",1.2,"0;0.25;0.5;1")+square(152,234,3,blue)+square(158,234,3,light)+square(164,234,3,blue),'data-part="working-activity"');
  return group(a+active,`data-part="working-prop" data-action="${id}"`);
}

function requestScene(ctx){
  const n=ctx.variant,shots=[];
  for(let f=0;f<5;f++){
    let a="";
    if(n===1){const tap=[10,0,9,0,10][f];a=rect(129,180,60,47,amber)+rect(135,185,48,42,palette.black)+rect(139,189,36,32,gray)+square(166,204,5,amber)+square(197+tap,199,13,ink);if(f===1||f===3)a+=burst(187,205,0,amber);}
    if(n===2){const w=[8,23,43,61,61][f];a=rect(114,177,5,48,light)+path(`M119 180h${w}v24h-${w}Z`,amber)+rect(107,225,24,4,gray);if(f>=2)a+=square(130,188,5,palette.black)+square(141,188,5,palette.black)+square(152,188,5,palette.black);}
    if(n===3){const dx=[0,-8,8,-5,0][f];a=at(132+dx,182,path("M18 0h20v6h7v23h8v7H0v-7h8V6h10Z",amber)+rect(21,36,11,6,light)+rect(22,-5,11,5,gray));if(f>0&&f<4)a+=square(117-dx,194,5,amber)+square(196-dx,194,5,amber);}
    shots.push(a);
  }
  return story(ctx,shots,3.6,["door-request","flag-request","bell-request"][n-1],true,4);
}
function completionScene(ctx){
  const n=ctx.variant;
  if(n===1){
    const confetti=Array.from({length:10},(_,i)=>at(54+i*23,199,group(move(ctx,`0 18;${i%2?5:-5} -20;${i%2?9:-9} -10;0 20;0 20`,3.6,"0;0.25;0.5;0.8;1","1")+opacity(ctx,"0;1;1;0;0",3.6,"0;0.1;0.5;0.9;1","1")+square(0,0,5,[ink,coral,blue][i%3]),'opacity="0"'))).join("");
    return group(trophy(ctx)+confetti,'data-part="completion-cue" data-action="trophy-fountain"');
  }
  if(n===2){
    // Home is open, so a finite playback never strands Boop behind a curtain.
    const curtains=[12,34,72,105,72,34,12].map(w=>rect(0,0,w,232,"#B75242")+rect(320-w,0,w,232,"#B75242")+rect(Math.max(0,w-9),0,6,232,"#D97545")+rect(323-w,0,6,232,"#D97545"));
    const scroll=rect(114,185,92,33,ink)+rect(109,181,9,41,light)+rect(202,181,9,41,light)+rect(125,194,68,4,gray)+rect(125,203,48,4,gray);
    const curtainMotion=timedStory(ctx,curtains,ctx.loopSeconds||7.2,"curtain-reveal",[0,.03,.06,.09,.15,.22,.30,1],[0,1,2,3,4,5,6,0],0);
    return group(curtainMotion+(ctx.mood==="proud"?"":scroll)+star(152,22,24,ctx.ink),'data-part="completion-cue" data-action="curtain-call"');
  }
  const cup=group(path("M6 0h18v4h6v10h-7v4h-5v6h7v5H5v-5h7v-6H5v-4H0V4h6Z",ctx.ink)+rect(9,3,12,9,ink),'data-part="trophy"');
  const podium=[0,5,12,18,18].map(h=>rect(81,236-h,51,h+3,ctx.ink)+rect(132,220-h,56,h+19,ctx.ink)+rect(188,236-h,51,h+3,ctx.ink)+rect(136,223-h,48,4,ink)+at(145,191-h,cup));
  return group(story(ctx,podium,3.2,"podium-rise",true,4),'data-part="completion-cue" data-action="podium"');
}
function listeningScene(ctx){
  const n=ctx.variant;
  if(n===1)return group(path("M31 62V30h32v5H36v27ZM257 30h32v10h-5v-5h-27ZM31 125h5v28h27v5H31ZM284 125h5v33h-32v-5h27Z",blue),'data-part="attention-frame"');
  if(n===2)return group(path("M18 91V53h8V37h16V25h236v12h16v16h8v38h-8V57h-8V43h-16V33H50v10H34v14h-8v34Z",gray)+rect(16,87,19,50,blue)+rect(285,87,19,50,blue)+rect(20,94,7,36,light)+rect(294,94,7,36,light),'data-part="headphones"');
  return group(path("M234 163h12v6h12v7h13v34h-13v6h-12v7h-12v-19h-30v-13h30Z",amber)+rect(262,180,5,26,palette.black)+rect(201,188,9,18,light)+rect(222,215,5,13,gray),'data-part="listening-trumpet"');
}

return {sceneSpecs,activeNames,activeCaptions,grumpyTiming,grumpyActing,drawWorkScene,requestScene,completionScene,listeningScene};}};const cache={};function load(id){if(!cache[id]){if(!modules[id])throw new Error('Missing module '+id);cache[id]=modules[id]();}return cache[id];}return {...load('bank.mjs'),...load('catalog.mjs'),...load('player.mjs'),...load('state-catalog.mjs'),...load('mood-catalog.mjs'),...load('mood-art.mjs'),states:load('state-catalog.mjs').stateOrder};})();
