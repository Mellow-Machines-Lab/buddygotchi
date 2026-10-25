// Boop's gel board in the Character Studio (characters/studio/): the board's
// own card (StudioBoard, the firmware as WebAssembly), with the slime's tools
// in its drawer. Review clips: each case of a set (review-sets.json, which
// the studio's server also takes as the clip names it may save) recorded
// from the board on its frozen clock, then played into a silent WebM. Sound
// sketches: each of the sounds the board's effects are cut from
// (design/slime-blob/sound/sfx.js), on its own.
(() => {
  const board = StudioBoard.adapter('boop', 'gel');
  const SETS = {activities: 'Representative activities', bridges: 'Directed mood bridges'};
  const SKETCHES = {squish: 'Gel squish', bounce: 'Soft landing', wobble: 'Elastic wobble', poke: 'Tiny poke',
    keyboard: 'Crisp key', tear: 'Tear plip', knock_ding: 'Knock → ding', complete: 'Success swell',
    failed: 'Failure cue', sneeze: 'Little sneeze', breath: 'Snore breath'};
  const here = document.currentScript.src;
  let cases = null;
  const loadCases = () => cases ??= fetch(new URL('review-sets.json', here))
    .then(r => r.ok ? r.json() : Promise.reject(Error('No review sets'))).then(j => j.cases);

  // A case's frames: an activity from a reset, 6.4 s; a bridge 1.6 s in its
  // first mood, then 4.8 s after the change.
  const framesOf = (instance, c) => instance.record(c.to ? {from: c.from, to: c.to, before: 40, after: 120}
                                                         : {from: c.from, before: 50, after: 110});
  // Recorded frames, played at their own pace into a silent WebM, the case's
  // id over them.
  async function webm(frames, id) {
    const canvas = document.createElement('canvas'), first = frames[0].image;
    canvas.width = 960;
    canvas.height = Math.round(960 * first.height / first.width) + 48;
    const ctx = canvas.getContext('2d'), stream = canvas.captureStream(25);
    const type = ['video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm'].find(t => MediaRecorder.isTypeSupported(t));
    const recorder = new MediaRecorder(stream, {...(type ? {mimeType: type} : {}), videoBitsPerSecond: 1400000});
    const chunks = [];
    recorder.addEventListener('dataavailable', e => { if (e.data.size) chunks.push(e.data); });
    const done = new Promise(ok => recorder.addEventListener('stop', ok));
    recorder.start();
    for (const frame of frames) {
      ctx.fillStyle = '#080b10';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(frame.image, 0, 48, canvas.width, canvas.height - 48);
      ctx.font = '20px ui-monospace, monospace';
      ctx.fillStyle = '#dceefa';
      ctx.fillText(`${id} · ${frame.ms} ms`, 22, 31);
      await new Promise(ok => setTimeout(ok, StudioBoard.FRAME_MS));
    }
    recorder.stop();
    stream.getTracks().forEach(track => track.stop());
    await done;
    return new Blob(chunks, {type: recorder.mimeType || 'video/webm'});
  }

  Studio.register('board-gel', {...board, create(ctx) {
    const instance = board.create(ctx);
    ctx.tools.insertAdjacentHTML('beforeend', `
    <section>
      <h4>Review clips</h4>
      <p>Records each case of a set from the board, on its frozen clock, as a silent clip to look at or save.</p>
      <div class="row">
        <label class="grow"><span class="visually-hidden">Review set</span><select data-review-set>${
          Object.entries(SETS).map(([id, label]) => `<option value="${id}">${label}</option>`).join('')}</select></label>
        <button type="button" data-record>Record review set</button>
        <button type="button" data-save-review disabled>Save review clips locally</button>
      </div>
      <p class="hint" data-record-status>Saving needs the studio's server started with --capture-dir.</p>
      <div class="gallery" data-review-gallery></div>
    </section>
    <section>
      <h4>Sound sketches</h4>
      <p>Each of the sounds the board's effects are cut from, on its own. Playing one mutes the board.</p>
      <div class="row wrap" data-sketches></div>
      <p class="hint" data-sketch-status aria-live="polite">Silent until you pick one.</p>
    </section>`);
    const $ = selector => ctx.tools.querySelector(selector);
    let recording = false, stopped = false, clips = [], save = null, sketches = 0;
    const status = text => { $('[data-record-status]').textContent = text; };
    const saveReady = () => { $('[data-save-review]').disabled = recording || !clips.length || !save?.enabled; };

    $('[data-record]').addEventListener('click', async () => {
      if (recording) { stopped = true; return; }
      if (typeof MediaRecorder === 'undefined') return status('Recording needs a browser with MediaRecorder.');
      recording = true, stopped = false;
      $('[data-record]').textContent = 'Stop recording';
      for (const link of $('[data-review-gallery]').querySelectorAll('a')) URL.revokeObjectURL(link.href);
      $('[data-review-gallery]').replaceChildren();
      clips = [];
      saveReady();
      const set = $('[data-review-set]').value;
      let list = [];
      try {
        if (location.protocol === 'http:' && !save)
          save = await fetch('/review-capture-config').then(r => r.ok ? r.json() : null).catch(() => null);
        list = (await loadCases()).filter(c => c.set === set);
        for (const [i, c] of list.entries()) {
          if (stopped) break;
          status(`Recording ${i + 1}/${list.length}: ${c.id}`);
          const frames = await framesOf(instance, c);
          if (!frames) break;
          const blob = await webm(frames, c.id), url = URL.createObjectURL(blob);
          frames.forEach(f => f.image?.close());
          const card = document.createElement('article'), title = document.createElement('p'),
                video = document.createElement('video'), link = document.createElement('a');
          title.textContent = c.id;
          Object.assign(video, {controls: true, muted: true, preload: 'metadata', src: url});
          Object.assign(link, {href: url, download: `${c.id}.webm`, textContent: `Save ${c.id}`});
          card.append(title, video, link);
          $('[data-review-gallery]').append(card);
          clips.push({name: `${c.id}.webm`, blob});
        }
        status(`${clips.length} of ${list.length} clips, from the board. Art review is pending.`);
      } catch (error) {
        status(`Recording stopped: ${error.message}`);
      } finally {
        recording = false;
        $('[data-record]').textContent = 'Record review set';
        instance.setPaused(instance.paused);  // the stage takes its board back
        saveReady();
      }
    });
    $('[data-save-review]').addEventListener('click', async () => {
      $('[data-save-review]').disabled = true;
      try {
        for (const [i, clip] of clips.entries()) {
          status(`Saving ${i + 1}/${clips.length}: ${clip.name}`);
          const r = await fetch(`/review-captures/${encodeURIComponent(clip.name)}`, {method: 'POST', body: clip.blob,
            headers: {'Content-Type': 'video/webm', 'X-Boop-Review-Token': save.token}});
          if (!r.ok) throw Error(`${clip.name}: ${r.status === 409 ? 'it exists already; choose a fresh capture directory' : `not saved (${r.status})`}`);
        }
        status(`Saved ${clips.length} clips in ${save.directory}.`);
      } catch (error) {
        status(error.message);
      } finally {
        saveReady();
      }
    });

    for (const [name, label] of Object.entries(SKETCHES)) {
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = label;
      b.addEventListener('click', async () => {
        try {
          ctx.setSound(false);
          const r = await SlimeSFX.play(name, {variant: sketches++ % 3, seed: 1729 + sketches});
          $('[data-sketch-status]').textContent = `${label} · sketch ${r.variant + 1} · ${r.duration.toFixed(2)} s`;
        } catch (error) {
          $('[data-sketch-status]').textContent = error.message;
        }
      });
      $('[data-sketches]').append(b);
    }
    const quiet = document.createElement('button');
    quiet.type = 'button';
    quiet.textContent = 'Stop sound';
    quiet.addEventListener('click', () => { SlimeSFX.stop(); $('[data-sketch-status]').textContent = 'Sound stopped.'; });
    $('[data-sketches]').append(quiet);
    const hidden = () => { if (document.hidden) SlimeSFX.stop(); };
    document.addEventListener('visibilitychange', hidden);

    const destroy = instance.destroy;
    instance.busy = () => recording;
    instance.destroy = () => {
      stopped = true;
      SlimeSFX.stop();
      document.removeEventListener('visibilitychange', hidden);
      ctx.tools.replaceChildren();
      destroy();
    };
    return instance;
  }});
})();
