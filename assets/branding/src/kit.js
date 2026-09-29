/*
  브랜딩 공용 그리기 도구. 아이콘·썸네일 A·B 가 같은 캐릭터와 제목 스타일을 쓰게 한다.

  KIT.defs            그라디언트 모음. 각 <svg> 의 <defs> 안에 한 번 넣는다.
  KIT.chibi(o)        머리가 큰 꼬마 한 명. 원점은 두 발 사이 바닥, 키 약 306.
  KIT.sparkle(x,y,r)  네 갈래 반짝임.
  KIT.sticker(x,y,r)  칭찬스티커(꽃잎 흰 테 + 노란 웃는 얼굴. 동전으로 보이지 않게).
  KIT.title(o)        남색 외곽선 + 흰 테 + 색 글자로 된 제목 한 줄.

  chibi 옵션(전부 생략 가능):
    hair, hairStyle('short'|'bob'|'pigtails'|'long'), cowlick
    top, outfit('tee'|'blazer'|'space'|'tiger'|'gold'), pants, skirt, shoes
    armL, armR  팔 각도(도). 0 = 내림, 120 = 옆으로 들어 손 흔들기
    eyes('open'|'happy'|'wink'), mouth('smile'|'grin')
    acc: ['cap:#색', 'glasses:#색', 'hairpin', 'bow:#색', 'crown', 'helmet', 'tigerHood',
          'medal:#리본색', 'bowtie:#색', 'tie:#색', 'armband:#색', 'badge']
*/
const KIT = (() => {
  const OL = '#2a2550';
  const ol = (w = 5) => `stroke="${OL}" stroke-width="${w}" stroke-linejoin="round" stroke-linecap="round"`;
  const SKIN = '#ffdcc2';
  const INK = '#2b2238';

  const defs = `
    <linearGradient id="kitTitleYellow" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff7b8"/><stop offset=".5" stop-color="#ffd43b"/><stop offset="1" stop-color="#ffab1f"/></linearGradient>
    <linearGradient id="kitTitleWhite" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff"/><stop offset=".6" stop-color="#ffffff"/><stop offset="1" stop-color="#d6ecff"/></linearGradient>
    <linearGradient id="kitTitleGreen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#c8ffe6"/><stop offset=".55" stop-color="#4ee0a6"/><stop offset="1" stop-color="#20b985"/></linearGradient>
    <linearGradient id="kitTitleBlue" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#d8ecff"/><stop offset=".55" stop-color="#7ab8ff"/><stop offset="1" stop-color="#4f8ff5"/></linearGradient>
    <radialGradient id="kitSticker" cx=".36" cy=".3" r=".8">
      <stop offset="0" stop-color="#fff6b3"/><stop offset=".55" stop-color="#ffd23a"/><stop offset="1" stop-color="#f7a90f"/></radialGradient>
    <linearGradient id="kitGold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff0a0"/><stop offset=".45" stop-color="#ffcf3a"/><stop offset="1" stop-color="#e99a10"/></linearGradient>
    <radialGradient id="kitHelmet" cx=".35" cy=".3" r=".8">
      <stop offset="0" stop-color="#ffffff" stop-opacity=".4"/><stop offset=".5" stop-color="#cfeaff" stop-opacity=".1"/>
      <stop offset="1" stop-color="#8fc7ff" stop-opacity=".3"/></radialGradient>`;

  const star = (cx, cy, r, fill, extra = '') => {
    let d = '';
    for (let i = 0; i < 10; i++) {
      const a = -Math.PI / 2 + (i * Math.PI) / 5;
      const rr = i % 2 ? r * 0.48 : r;
      d += `${i ? 'L' : 'M'} ${(cx + rr * Math.cos(a)).toFixed(1)} ${(cy + rr * Math.sin(a)).toFixed(1)} `;
    }
    return `<path d="${d}Z" fill="${fill}" ${extra}/>`;
  };

  const sparkle = (x, y, r, fill = '#fff', op = 1) => {
    const k = r * 0.16;
    return `<path transform="translate(${x} ${y})" opacity="${op}" fill="${fill}" d="M 0 ${-r} C ${k} ${-k} ${k} ${-k} ${r} 0 C ${k} ${k} ${k} ${k} 0 ${r} C ${-k} ${k} ${-k} ${k} ${-r} 0 C ${-k} ${-k} ${-k} ${-k} 0 ${-r} Z"/>`;
  };

  // 칭찬스티커. 동전처럼 보이지 않도록 꽃잎 테두리 + 웃는 얼굴로 그린다.
  const sticker = (x, y, r, rot = 0) => {
    let petals = '';
    for (let i = 0; i < 12; i++) {
      const a = (i * Math.PI * 2) / 12;
      petals += `<circle cx="${(Math.cos(a) * r * 0.86).toFixed(1)}" cy="${(Math.sin(a) * r * 0.86).toFixed(1)}" r="${(r * 0.26).toFixed(1)}"/>`;
    }
    return `<g transform="translate(${x} ${y}) rotate(${rot})">
      <g fill="#fff" stroke="${OL}" stroke-width="${r * 0.1}">${petals}</g>
      <circle r="${r * 0.9}" fill="#fff"/>
      <g fill="#fff">${petals}</g>
      <circle r="${r * 0.74}" fill="url(#kitSticker)" stroke="#f0a010" stroke-width="${r * 0.05}"/>
      <ellipse cx="${-r * 0.24}" cy="${-r * 0.12}" rx="${r * 0.08}" ry="${r * 0.12}" fill="${INK}"/>
      <ellipse cx="${r * 0.24}" cy="${-r * 0.12}" rx="${r * 0.08}" ry="${r * 0.12}" fill="${INK}"/>
      <path d="M ${-r * 0.32} ${r * 0.14} Q 0 ${r * 0.48} ${r * 0.32} ${r * 0.14}" fill="none" stroke="${INK}" stroke-width="${r * 0.09}" stroke-linecap="round"/>
      <path d="M ${-r * 0.5} ${-r * 0.3} A ${r * 0.56} ${r * 0.56} 0 0 1 ${-r * 0.12} ${-r * 0.56}" fill="none" stroke="#fff" stroke-width="${r * 0.09}" stroke-linecap="round" opacity=".85"/>
    </g>`;
  };

  function arm(side, deg, sleeve, band) {
    return `<g transform="translate(${side * 44} -122) rotate(${-side * deg})">
      <rect x="-15" y="-8" width="30" height="66" rx="15" fill="${sleeve}" ${ol()}/>
      ${band ? `<rect x="-16" y="16" width="32" height="18" fill="${band}" ${ol(4)}/><rect x="-14" y="21" width="28" height="4" fill="#fff" opacity=".75"/>` : ''}
      <circle cx="0" cy="62" r="16" fill="${SKIN}" ${ol()}/>
    </g>`;
  }

  function legs(o) {
    const p = o.pants || '#3d4f7a';
    const sh = o.shoes || '#ffffff';
    let s = `<rect x="-38" y="-62" width="32" height="54" rx="12" fill="${p}" ${ol()}/>
      <rect x="6" y="-62" width="32" height="54" rx="12" fill="${p}" ${ol()}/>`;
    if (o.skirt) {
      s = `<rect x="-34" y="-62" width="26" height="54" rx="11" fill="${SKIN}" ${ol()}/>
        <rect x="8" y="-62" width="26" height="54" rx="11" fill="${SKIN}" ${ol()}/>
        <path d="M -52 -84 L 52 -84 L 64 -44 Q 0 -34 -64 -44 Z" fill="${o.skirt}" ${ol()}/>`;
    }
    s += `<path d="M -48 -1 Q -48 -24 -24 -24 Q -2 -24 -2 -1 Z" fill="${sh}" ${ol()}/>
      <path d="M 2 -1 Q 2 -24 24 -24 Q 48 -24 48 -1 Z" fill="${sh}" ${ol()}/>`;
    return s;
  }

  function torso(o, has) {
    const outfit = o.outfit || 'tee';
    const top = o.top || '#6aa8ff';
    const body = 'M -50 -134 Q 0 -146 50 -134 Q 60 -94 60 -52 Q 0 -40 -60 -52 Q -60 -94 -50 -134 Z';
    let s = `<path d="${body}" fill="${top}" ${ol()}/>`;
    // 오른쪽 그늘
    s += `<path d="M 34 -138 Q 44 -136 50 -134 Q 60 -94 60 -52 Q 48 -48 36 -46 Q 40 -94 34 -138 Z" fill="#000" opacity=".08"/>`;
    if (outfit === 'tee') {
      s += `<path d="M -20 -140 Q 0 -118 20 -140" fill="none" ${ol(5)}/>`;
    } else if (outfit === 'blazer' || outfit === 'gold') {
      s += `<path d="M -24 -142 L 0 -92 L 24 -142 Z" fill="#fff" ${ol(4)}/>`;
      s += `<path d="M -24 -142 L -4 -98 L -30 -110 Z M 24 -142 L 4 -98 L 30 -110 Z" fill="#000" opacity=".12"/>`;
      s += `<circle cx="0" cy="-74" r="4.5" fill="${OL}" opacity=".55"/><circle cx="0" cy="-60" r="4.5" fill="${OL}" opacity=".55"/>`;
      if (outfit === 'gold') {
        s += `<path d="M -40 -122 Q -46 -96 -44 -66" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" opacity=".7"/>`;
      }
    } else if (outfit === 'space') {
      s += `<rect x="-26" y="-112" width="52" height="40" rx="9" fill="#e7eefb" ${ol(4)}/>
        <circle cx="-12" cy="-92" r="6" fill="#ff9b54"/><circle cx="4" cy="-92" r="6" fill="#60a5fa"/><circle cx="18" cy="-92" r="4" fill="#fbbf24"/>
        <path d="M -60 -60 Q 0 -48 60 -60" fill="none" stroke="#b9c6dc" stroke-width="8"/>`;
    } else if (outfit === 'tiger') {
      s += `<path d="M -58 -110 L -36 -104 L -58 -96 Z M -60 -84 L -34 -78 L -60 -70 Z M 58 -110 L 36 -104 L 58 -96 Z M 60 -84 L 34 -78 L 60 -70 Z" fill="#3b3a4a"/>
        <path d="M -22 -118 Q 0 -104 22 -118 Q 26 -80 0 -70 Q -26 -80 -22 -118 Z" fill="#fff" ${ol(3)}/>`;
    }
    if (has('bowtie')) {
      const c = has('bowtie');
      s += `<path d="M 0 -110 L -24 -122 L -24 -96 Z M 0 -110 L 24 -122 L 24 -96 Z" fill="${c}" ${ol(4)}/><circle cx="0" cy="-110" r="7" fill="${c}" ${ol(4)}/>`;
    }
    if (has('tie')) {
      const c = has('tie');
      s += `<path d="M -8 -136 L 8 -136 L 12 -84 L 0 -72 L -12 -84 Z" fill="${c}" ${ol(4)}/>`;
    }
    if (has('medal')) {
      const c = has('medal');
      s += `<path d="M -22 -140 L -2 -96 L 8 -100 L -8 -140 Z" fill="${c}" ${ol(3)}/>
        <path d="M 22 -140 L 2 -96 L -8 -100 L 8 -140 Z" fill="${c}" ${ol(3)}/>
        <circle cx="0" cy="-84" r="17" fill="url(#kitGold)" ${ol(4)}/>` + star(0, -83, 9, '#fff6c8');
    }
    if (has('badge')) {
      s += `<circle cx="-32" cy="-100" r="13" fill="url(#kitGold)" ${ol(3)}/>` + star(-32, -99, 7, '#fff6c8');
    }
    return s;
  }

  function hairShapes(o, has) {
    const hc = o.hair || '#3a2a2a';
    const style = o.hairStyle || 'short';
    let back = '';
    let front = '';
    if (style === 'bob' || style === 'pigtails' || style === 'long') {
      const bottom = style === 'long' ? 118 : 78;
      back = `<path d="M -106 -4 C -110 -72 -62 -104 0 -104 C 62 -104 110 -72 106 -4 L 110 ${bottom - 8} Q 102 ${bottom + 12} 80 ${bottom} L -80 ${bottom} Q -102 ${bottom + 12} -110 ${bottom - 8} Z" fill="${hc}" ${ol()}/>`;
      if (style === 'pigtails') {
        back += `<ellipse cx="-122" cy="34" rx="26" ry="44" transform="rotate(14 -122 34)" fill="${hc}" ${ol()}/>
          <ellipse cx="122" cy="34" rx="26" ry="44" transform="rotate(-14 122 34)" fill="${hc}" ${ol()}/>`;
      }
      front = `<path d="M -104 10 C -106 -64 -62 -102 0 -102 C 62 -102 106 -64 104 10 L 102 56 Q 96 70 84 60 L 82 2 Q 74 -22 54 -18 Q 38 -38 16 -22 Q -2 -40 -22 -22 Q -44 -38 -60 -16 Q -78 -20 -82 2 L -84 60 Q -96 70 -102 56 Z" fill="${hc}" ${ol()}/>`;
      if (style === 'pigtails') {
        front += `<circle cx="-104" cy="2" r="10" fill="#ff8fb1" ${ol(4)}/><circle cx="104" cy="2" r="10" fill="#ff8fb1" ${ol(4)}/>`;
      }
    } else {
      front = `<path d="M -102 4 C -106 -66 -62 -100 0 -100 C 62 -100 106 -66 102 4 L 90 6 Q 88 -8 78 -14 Q 62 -28 46 -16 Q 30 -36 10 -22 Q -10 -38 -30 -20 Q -50 -32 -66 -14 Q -84 -12 -90 6 Z" fill="${hc}" ${ol()}/>`;
    }
    if (o.cowlick) {
      front += `<path d="M -6 -98 Q 0 -140 34 -130 Q 12 -122 12 -98 Z" fill="${hc}" ${ol()}/>`;
    }
    front += `<path d="M -66 -60 Q -40 -84 -6 -88" fill="none" stroke="#fff" stroke-width="9" stroke-linecap="round" opacity=".28"/>`;
    return { back, front };
  }

  function face(o) {
    const e = o.eyes || 'open';
    let s = '';
    const openEye = (x) => `<ellipse cx="${x}" cy="16" rx="13" ry="17.5" fill="${INK}"/>
      <circle cx="${x - 4}" cy="8" r="5.8" fill="#fff"/><circle cx="${x + 4.5}" cy="23" r="2.8" fill="#fff" opacity=".9"/>`;
    const happyEye = (x) => `<path d="M ${x - 15} 22 Q ${x} 2 ${x + 15} 22" fill="none" stroke="${INK}" stroke-width="7.5" stroke-linecap="round"/>`;
    if (e === 'open') s += openEye(-36) + openEye(36);
    else if (e === 'happy') s += happyEye(-36) + happyEye(36);
    else if (e === 'wink') s += openEye(-36) + happyEye(36);
    s += `<path d="M -50 -12 Q -37 -21 -24 -13" fill="none" stroke="${INK}" stroke-width="5.5" stroke-linecap="round" opacity=".8"/>
      <path d="M 50 -12 Q 37 -21 24 -13" fill="none" stroke="${INK}" stroke-width="5.5" stroke-linecap="round" opacity=".8"/>`;
    s += `<ellipse cx="-60" cy="42" rx="15" ry="9" fill="#ff8aa0" opacity=".55"/><ellipse cx="60" cy="42" rx="15" ry="9" fill="#ff8aa0" opacity=".55"/>`;
    if ((o.mouth || 'smile') === 'grin') {
      s += `<path d="M -28 38 Q 0 82 28 38 Q 0 46 -28 38 Z" fill="#8a2f45" ${ol(4)}/>
        <path d="M -22 42 Q 0 48 22 42 L 20 48 Q 0 54 -20 48 Z" fill="#fff"/>
        <path d="M -12 66 Q 0 74 12 66 Q 0 58 -12 66 Z" fill="#ff7d93"/>`;
    } else {
      s += `<path d="M -20 42 Q 0 70 20 42 Q 0 48 -20 42 Z" fill="#8a2f45" ${ol(4)}/>
        <path d="M -9 57 Q 0 64 9 57 Q 0 52 -9 57 Z" fill="#ff7d93"/>`;
    }
    return s;
  }

  function head(o, has) {
    let s = '<g transform="translate(0 -210)">';
    if (has('tigerHood')) {
      s += `<g>
        <circle cx="-74" cy="-76" r="28" fill="#fff" ${ol()}/><circle cx="-74" cy="-76" r="13" fill="#ffb3c4"/>
        <circle cx="74" cy="-76" r="28" fill="#fff" ${ol()}/><circle cx="74" cy="-76" r="13" fill="#ffb3c4"/>
        <path d="M -110 4 C -112 -70 -64 -108 0 -108 C 64 -108 112 -70 110 4 C 112 60 80 104 0 104 C -80 104 -112 60 -110 4 Z" fill="#fbfdff" ${ol()}/>
        <path d="M -14 -106 L 0 -76 L 14 -106 Z M -44 -100 L -30 -80 L -24 -104 Z M 44 -100 L 30 -80 L 24 -104 Z" fill="#3b3a4a"/>
        <path d="M -110 -20 L -86 -12 L -110 -2 Z M -108 24 L -84 30 L -106 40 Z M 110 -20 L 86 -12 L 110 -2 Z M 108 24 L 84 30 L 106 40 Z" fill="#3b3a4a"/>
        <ellipse cx="-30" cy="-58" rx="7" ry="9" fill="${INK}"/><ellipse cx="30" cy="-58" rx="7" ry="9" fill="${INK}"/>
        <path d="M -8 -44 L 8 -44 L 0 -36 Z" fill="#ff9fb4"/>
        <ellipse cx="0" cy="22" rx="80" ry="70" fill="${SKIN}" ${ol(4)}/>
        <path d="M -66 -8 Q -58 -44 0 -48 Q 58 -44 66 -8 Q 50 -22 34 -14 Q 18 -30 0 -18 Q -18 -30 -34 -14 Q -50 -22 -66 -8 Z" fill="${o.hair || '#3a2a2a'}" ${ol(3)}/>`;
      s += `<g transform="translate(0 8) scale(.9)">${face(o)}</g>`;
      s += '</g></g>';
      return s;
    }
    const { back, front } = hairShapes(o, has);
    s += back;
    s += `<circle cx="-93" cy="16" r="17" fill="${SKIN}" ${ol()}/><circle cx="93" cy="16" r="17" fill="${SKIN}" ${ol()}/>`;
    s += `<ellipse cx="0" cy="0" rx="96" ry="88" fill="${SKIN}" ${ol()}/>`;
    s += face(o);
    s += front;
    if (has('cap')) {
      const c = has('cap');
      s += `<path d="M -100 -8 C -100 -78 -56 -104 0 -104 C 56 -104 100 -78 100 -8 Q 0 -30 -100 -8 Z" fill="${c}" ${ol()}/>
        <path d="M -88 -12 Q 0 -40 88 -12 Q 76 12 0 12 Q -76 12 -88 -12 Z" fill="${c}" ${ol()}/>
        <path d="M -88 -12 Q 0 -40 88 -12 Q 76 12 0 12 Q -76 12 -88 -12 Z" fill="#000" opacity=".15"/>
        <circle cx="0" cy="-102" r="8" fill="${c}" ${ol(4)}/>
        <path d="M -60 -64 Q -34 -86 -4 -90" fill="none" stroke="#fff" stroke-width="9" stroke-linecap="round" opacity=".35"/>`;
    }
    if (has('glasses')) {
      const c = has('glasses');
      s += `<g fill="#fff" fill-opacity=".18" stroke="${c}" stroke-width="6.5">
        <circle cx="-36" cy="16" r="25"/><circle cx="36" cy="16" r="25"/></g>
        <path d="M -11 12 Q 0 6 11 12" fill="none" stroke="${c}" stroke-width="6"/>`;
    }
    if (has('hairpin')) s += star(-64, -30, 16, '#ffd43b', ol(3.5));
    if (has('bow')) {
      const c = has('bow');
      s += `<g transform="translate(62 -74) rotate(18)"><path d="M 0 0 L -30 -18 L -30 18 Z M 0 0 L 30 -18 L 30 18 Z" fill="${c}" ${ol(4)}/><circle r="9" fill="${c}" ${ol(4)}/></g>`;
    }
    if (has('crown')) {
      s += `<g transform="translate(0 -106)"><path d="M -40 10 L -44 -30 L -20 -8 L 0 -38 L 20 -8 L 44 -30 L 40 10 Z" fill="url(#kitGold)" ${ol(4.5)}/>
        <circle cx="0" cy="-2" r="6" fill="#a78bfa"/></g>`;
    }
    if (has('helmet')) {
      s += `<circle cx="0" cy="-4" r="130" fill="url(#kitHelmet)" stroke="${OL}" stroke-width="16"/>
        <circle cx="0" cy="-4" r="130" fill="none" stroke="#eef5ff" stroke-width="8"/>
        <path d="M -104 -54 A 116 116 0 0 1 -36 -118" fill="none" stroke="#fff" stroke-width="14" stroke-linecap="round" opacity=".9"/>
        <circle cx="-110" cy="-10" r="7" fill="#fff" opacity=".9"/>
        <path d="M 76 -104 L 104 -150" ${ol(6)}/>` + star(108, -158, 18, '#ffd43b', ol(4));
    }
    s += '</g>';
    return s;
  }

  function chibi(o = {}) {
    const accs = o.acc || [];
    const has = (name) => {
      for (const a of accs) {
        const [n, v] = a.split(':');
        if (n === name) return v || true;
      }
      return false;
    };
    const sleeve = o.sleeve || o.top || '#6aa8ff';
    let s = '';
    if (o.shadow !== false) s += `<ellipse cx="0" cy="0" rx="74" ry="13" fill="#1a3a2a" opacity=".18"/>`;
    s += legs(o);
    s += torso(o, has);
    if (has('helmet')) {
      s += `<rect x="-70" y="-146" width="140" height="30" rx="14" fill="#dfe8f5" ${ol()}/>`;
    }
    s += arm(-1, o.armL || 0, sleeve, has('armband'));
    s += arm(1, o.armR || 0, sleeve, false);
    s += head(o, has);
    return s;
  }

  function title(o) {
    const { x, y, size, spans, anchor = 'middle', rot = 0 } = o;
    const W = o.outline ?? size * 0.24;
    const ls = (o.ls ?? 0.01) * size;
    const base = `x="${x}" y="${y}" font-size="${size}" text-anchor="${anchor}" letter-spacing="${ls}"`;
    const plain = spans.map((sp) => `<tspan${sp[2] ? ` dy="${sp[2]}"` : ''}>${sp[0]}</tspan>`).join('');
    const colored = spans.map((sp) => `<tspan fill="${sp[1]}"${sp[2] ? ` dy="${sp[2]}"` : ''}>${sp[0]}</tspan>`).join('');
    const shade = o.shade || '#1b1740';
    return `<g transform="rotate(${rot} ${x} ${y})" font-family="Apple SD Gothic Neo" font-weight="900"
        paint-order="stroke" stroke-linejoin="round" stroke-linecap="round">
      <text ${base} transform="translate(0 ${size * 0.08})" fill="${shade}" stroke="${shade}" stroke-width="${W}">${plain}</text>
      <text ${base} fill="${OL}" stroke="${OL}" stroke-width="${W}">${plain}</text>
      <text ${base} fill="#fff" stroke="#fff" stroke-width="${W * 0.4}">${plain}</text>
      <text ${base}>${colored}</text>
    </g>`;
  }

  return { OL, SKIN, defs, chibi, sparkle, sticker, star, title };
})();
