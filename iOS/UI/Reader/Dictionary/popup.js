//
//  popup.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  Copyright © 2023-2025 Yomitan Authors.
//  Copyright © 2021-2022 Yomichan Authors.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

const KANJI_RANGE = '\u4E00-\u9FFF\u3400-\u4DBF\uF900-\uFAFF\u3005';
const KANJI_PATTERN = new RegExp(`[${KANJI_RANGE}]`);
const KANJI_SEGMENT_PATTERN = new RegExp(`[${KANJI_RANGE}]+|[^${KANJI_RANGE}]+`, 'g');
const KANA_PATTERN = /[\u3040-\u30FF\uFF66-\uFF9F]/;
const CJK_PATTERN = new RegExp(`[${KANJI_RANGE}]`);
const DEFAULT_HARMONIC_RANK = '9999999';
const SMALL_KANA_SET = new Set('ぁぃぅぇぉゃゅょゎァィゥェォャュョヮ');
const NUMERIC_TAG = /^\d+$/;
// this might not cover every tag
const POS_TAGS = new Set(['n', 'adj-i', 'adj-na', 'adj-no', 'v1', 'vk', 'vs', 'vs-i', 'vs-s', 'vz', 'vi', 'vt']);
const audioUrls = {};
let currentAudio = null;
let lastSelection = '';

function el(tag, props = {}, children = []) {
    const element = document.createElement(tag);
    for (const [key, value] of Object.entries(props)) {
        if (key in element) {
            element[key] = value;
        } else {
            element.setAttribute(key, value);
        }
    }
    
    if (children.length) {
        element.append(...children);
    }
    
    return element;
}

function toHiragana(text) {
    return text.replace(/[\u30A1-\u30F6]/g, ch => String.fromCharCode(ch.charCodeAt(0) - 0x60));
}

function toKebabCase(str) {
    return str.replace(/([A-Z])/g, (_, c, i) => (i ? '-' : '') + c.toLowerCase());
}

// https://github.com/yomidevs/yomitan/blob/c0abb9e98a15aeb6b6f8f6e2d91fe5e54240b54a/ext/js/language/ja/japanese.js#L332
function isStringPartiallyJapanese(text) {
    if (!text) {
        return false;
    }
    return KANA_PATTERN.test(text) || CJK_PATTERN.test(text);
}

// https://github.com/yomidevs/yomitan/blob/c0abb9e98a15aeb6b6f8f6e2d91fe5e54240b54a/ext/js/language/zh/chinese.js#L54
function isStringPartiallyChinese(text) {
    if (!text) {
        return false;
    }
    return CJK_PATTERN.test(text) || /[\u3100-\u312F\u31A0-\u31BF]/.test(text);
}

// https://github.com/yomidevs/yomitan/blob/c0abb9e98a15aeb6b6f8f6e2d91fe5e54240b54a/ext/js/language/text-utilities.js#L28
function getLanguageFromText(text, language) {
    const partiallyJapanese = isStringPartiallyJapanese(text);
    const partiallyChinese = isStringPartiallyChinese(text);
    if (!['zh', 'yue'].includes(language ?? '')) {
        if (partiallyJapanese) {
            return 'ja';
        }
        if (partiallyChinese) {
            return 'zh';
        }
    }
    return language ?? null;
}

function openExternalLink(url) {
    webkit.messageHandlers.openLink.postMessage(url);
}

function showDescription(element) {
    const description = element.getAttribute('data-description');
    if (!description) {
        return;
    }
    const overlay = document.querySelector('.overlay');
    document.querySelector('.overlay-content').textContent = description;
    overlay.style.display = 'block';
}

function closeOverlay() {
    document.querySelector('.overlay').style.display = 'none';
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L171
function createFuriganaSegment(text, reading) {
    return {text, reading};
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L242
function getFuriganaKanaSegments(text, reading) {
    const textLength = text.length;
    const newSegments = [];
    let start = 0;
    let state = (reading[0] === text[0]);
    for (let i = 1; i < textLength; ++i) {
        const newState = (reading[i] === text[i]);
        if (state === newState) { continue; }
        newSegments.push(createFuriganaSegment(text.substring(start, i), state ? '' : reading.substring(start, i)));
        state = newState;
        start = i;
    }
    newSegments.push(createFuriganaSegment(text.substring(start, textLength), state ? '' : reading.substring(start, textLength)));
    return newSegments;
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L182
function segmentizeFurigana(reading, readingNormalized, groups, groupsStart) {
    const groupCount = groups.length - groupsStart;
    if (groupCount <= 0) {
        return reading.length === 0 ? [] : null;
    }

    const group = groups[groupsStart];
    const {isKana, text} = group;
    const textLength = text.length;
    if (isKana) {
        const {textNormalized} = group;
        if (textNormalized !== null && readingNormalized.startsWith(textNormalized)) {
            const segments = segmentizeFurigana(
                reading.substring(textLength),
                readingNormalized.substring(textLength),
                groups,
                groupsStart + 1,
            );
            if (segments !== null) {
                if (reading.startsWith(text)) {
                    segments.unshift(createFuriganaSegment(text, ''));
                } else {
                    segments.unshift(...getFuriganaKanaSegments(text, reading));
                }
                return segments;
            }
        }
        return null;
    } else {
        let result = null;
        for (let i = reading.length; i >= textLength; --i) {
            const segments = segmentizeFurigana(
                reading.substring(i),
                readingNormalized.substring(i),
                groups,
                groupsStart + 1,
            );
            if (segments !== null) {
                if (result !== null) {
                    // More than one way to segmentize the tail; mark as ambiguous
                    return null;
                }
                const segmentReading = reading.substring(0, i);
                segments.unshift(createFuriganaSegment(text, segmentReading));
                result = segments;
            }
            // There is only one way to segmentize the last non-kana group
            if (groupCount === 1) {
                break;
            }
        }
        return result;
    }
}

function segmentFurigana(expression, reading) {
    if (!reading || reading === expression) {
        return [[expression, '']];
    }

    const groups = [];
    const segmentMatches = expression.match(KANJI_SEGMENT_PATTERN) || [];
    for (const text of segmentMatches) {
        const isKana = !KANJI_PATTERN.test(text[0]);
        const textNormalized = isKana ? toHiragana(text) : null;
        groups.push({isKana, text, textNormalized});
    }

    const readingNormalized = toHiragana(reading);
    const segments = segmentizeFurigana(reading, readingNormalized, groups, 0);

    if (segments !== null) {
        return segments.map(seg => [seg.text, seg.reading]);
    }

    return [[expression, reading]];
}

function buildFuriganaEl(parent, expression, reading) {
    const segments = segmentFurigana(expression, reading);
    for (const [text, furigana] of segments) {
        if (furigana) {
            const ruby = el('ruby', {}, [text]);
            ruby.appendChild(el('rt', { textContent: furigana }));
            parent.appendChild(ruby);
        } else {
            parent.appendChild(document.createTextNode(text));
        }
    }
    return segments.length === 1 && segments[0][1];
}

function constructFuriganaPlain(expression, reading) {
    let result = '';
    for (const [text, furigana] of segmentFurigana(expression, reading)) {
        if (furigana) {
            result += `${text}[${furigana}]`;
        } else {
            // space to separate from next furigana segment, not sure if this is the correct solution
            result += `${text} `;
        }
    }
    return result;
}

// !AI SLOP! function to preprocess css
function constructDictCss(css, dictName) {
    if (!css) {
        return '';
    }
    const prefix = `.yomitan-glossary [data-dictionary="${dictName}"]`;
    const parts = [];
    let i = 0;
    while (i < css.length) {
        while (i < css.length && /\s/.test(css[i])) {
            parts.push(css[i++]);
        }
        if (css.slice(i, i + 2) === '/*') {
            const end = css.indexOf('*/', i + 2);
            if (end === -1) break;
            parts.push(css.slice(i, end + 2));
            i = end + 2;
            continue;
        }
        const bracePos = css.indexOf('{', i);
        if (bracePos === -1) break;
        const selectorPart = css.slice(i, bracePos);
        const selectors = selectorPart.split(',').map(s => {
            const trimmed = s.trim();
            if (!trimmed) return '';
            if (trimmed.startsWith('&')) {
                return s;
            }
            return `${prefix} ${trimmed}`;
        });
        parts.push(selectors.join(', '), ' {');
        i = bracePos + 1;
        let depth = 1;
        let blockStart = i;
        while (i < css.length && depth > 0) {
            if (css[i] === '{') depth++;
            else if (css[i] === '}') depth--;
            i++;
        }
        const blockContent = css.slice(blockStart, i - 1);
        if (blockContent.includes('{')) {
            let pos = 0;
            let properties = '';
            let nestedRules = '';
            while (pos < blockContent.length) {
                while (pos < blockContent.length && /\s/.test(blockContent[pos])) {
                    pos++;
                }
                if (pos >= blockContent.length) break;
                let nextSemi = blockContent.indexOf(';', pos);
                let nextBrace = blockContent.indexOf('{', pos);
                if (nextBrace !== -1 && (nextSemi === -1 || nextBrace < nextSemi)) {
                    let nestedDepth = 1;
                    let nestedEnd = nextBrace + 1;
                    while (nestedEnd < blockContent.length && nestedDepth > 0) {
                        if (blockContent[nestedEnd] === '{') nestedDepth++;
                        else if (blockContent[nestedEnd] === '}') nestedDepth--;
                        nestedEnd++;
                    }
                    nestedRules += blockContent.slice(pos, nestedEnd);
                    pos = nestedEnd;
                } else if (nextSemi !== -1) {
                    properties += blockContent.slice(pos, nextSemi + 1);
                    pos = nextSemi + 1;
                } else {
                    properties += blockContent.slice(pos);
                    break;
                }
            }
            parts.push(properties);
            if (nestedRules) {
                parts.push(constructDictCss(nestedRules, dictName));
            }
        } else {
            parts.push(blockContent);
        }
        parts.push('}');
    }
    return parts.join('');
}

// table styles taken from a jitendex glossary
function applyTableStyles(html) {
    const tableStyle = 'table-layout:auto;border-collapse:collapse;';
    const cellStyle = 'border-style:solid;padding:0.25em;vertical-align:top;border-width:1px;border-color:currentColor;';
    const thStyle = 'font-weight:bold;' + cellStyle;
    
    return html
    .replace(/<table(?=[>\s])/g, `<table style="${tableStyle}"`)
    .replace(/<th(?=[>\s])/g, `<th style="${thStyle}"`)
    .replace(/<td(?=[>\s])/g, `<td style="${cellStyle}"`);
}

const COMPACT_GLOSSARIES_ANKI = `.yomitan-glossary ul[data-sc-content="glossary"] > li:not(:first-child)::before, .yomitan-glossary .glossary-list > li:not(:first-child)::before { white-space: pre-wrap; content: " | "; display: inline; color: rgb(119, 119, 119); }
.yomitan-glossary ul[data-sc-content="glossary"] > li, .yomitan-glossary .glossary-list > li { display: inline; }
.yomitan-glossary ul[data-sc-content="glossary"], .yomitan-glossary .glossary-list { display: inline; list-style: none; padding-left: 0px; }`;

// the following two should roughly match the glossary format of yomitan and keep compatibility with notetypes like lapis
// 23.01.2026: this still has some differences
// 24.01.2026: should be a bit closer now
// 25.01.2026: fixed jmdict
// 19.02.2026: fixed jmdict legacy
// 24.03.2026: fixed compact glossaries for jmdict legacy
function constructSingleGlossaryHtml(entryIndex) {
    if (!window.lookupEntries || entryIndex >= window.lookupEntries.length) {
        return {};
    }
    
    const entry = window.lookupEntries[entryIndex];
    const glossaries = {};
    
    let lastDict = null;
    let currentGlossary = '';
    let prevTags = null;
    const flush = () => {
        if (!lastDict) {
            return;
        }
        
        let html = `<div style="text-align: left;" class="yomitan-glossary"><ol>${currentGlossary}</ol>`;
        const css = window.dictionaryStyles?.[lastDict] ?? '';
        if (css) {
            const scopedCss = constructDictCss(css, lastDict);
            const formatted = scopedCss
            .replace(/\s+/g, ' ')
            .replace(/\s*\{\s*/g, ' { ')
            .replace(/\s*\}\s*/g, ' }\n')
            .replace(/;\s*/g, '; ')
            .trim();
            html += `<style>${formatted}</style>`;
        }
        if (window.compactGlossariesAnki) {
            html += `<style>${COMPACT_GLOSSARIES_ANKI}</style>`;
        }
        html += `</div>`;
        
        glossaries[lastDict] = html;
        currentGlossary = '';
    };
    
    entry.glossaries.forEach(g => {
        const dictName = g.dictionary;
        const dictChanged = lastDict !== dictName;
        if (dictChanged) {
            flush();
            lastDict = dictName;
            prevTags = null;
        }
        
        const tempDiv = document.createElement('div');
        try {
            renderStructuredContent(tempDiv, JSON.parse(g.content), null, dictName, true);
        } catch {
            renderStructuredContent(tempDiv, g.content, null, dictName, true);
        }
        
        const parsedTags = parseTags(g.definitionTags).filter(tag => !NUMERIC_TAG.test(tag));
        const posTags = [...new Set(parsedTags.filter(isPartOfSpeech))].sort();
        const currentTags = JSON.stringify(posTags);
        const filteredTags = parsedTags.filter(tag => !isPartOfSpeech(tag) || !(prevTags !== null && prevTags === currentTags));
        const tags = filteredTags.length > 0 ? filteredTags.join(', ') : '';
        const content = applyTableStyles(tempDiv.innerHTML);
        let listIdentifier = '';
        if (dictChanged) {
            label = tags ? `(${tags}, ${dictName})` : `(${dictName})`;
        } else {
            label = tags ? `(${tags})` : '';
        }
        currentGlossary += `<li data-dictionary="${dictName}"><i>${label}</i> <span>${content}</span></li>`
        prevTags = currentTags;
    });
    
    flush();
    return glossaries;
}

function constructGlossaryHtml(entryIndex) {
    if (!window.lookupEntries || entryIndex >= window.lookupEntries.length) {
        return null;
    }
    
    const entry = window.lookupEntries[entryIndex];
    let glossaryItems = '';
    const styles = {};
    let lastDict = '';
    let prevTags = null;
    let index = 0;
    
    entry.glossaries.forEach(g => {
        const dictName = g.dictionary;
        
        const tempDiv = document.createElement('div');
        try {
            renderStructuredContent(tempDiv, JSON.parse(g.content), null, dictName, true);
        } catch {
            renderStructuredContent(tempDiv, g.content, null, dictName, true);
        }
        
        index++;
        let label = '';
        const parsedTags = parseTags(g.definitionTags).filter(tag => !NUMERIC_TAG.test(tag));
        const posTags = [...new Set(parsedTags.filter(isPartOfSpeech))].sort();
        const currentTags = JSON.stringify(posTags);
        const filteredTags = parsedTags.filter(tag => !isPartOfSpeech(tag) || !(prevTags !== null && prevTags === currentTags));
        const tags = filteredTags.length > 0 ? filteredTags.join(', ') : '';
        if (dictName !== lastDict) {
            index = 1;
            lastDict = dictName;
            label = tags ? `(${index}, ${tags}, ${dictName})` : `(${index}, ${dictName})`
        }
        else {
            label = tags ? `(${index}, ${tags})` : `(${index})`
        }
        
        glossaryItems += `<li data-dictionary="${dictName}"><i>${label}</i> <span>${applyTableStyles(tempDiv.innerHTML)}</span></li>`;
        prevTags = currentTags;
        
        const css = window.dictionaryStyles?.[dictName];
        if (css && !styles[dictName]) {
            styles[dictName] = css;
        }
    });
    
    let result = '<div style="text-align: left;" class="yomitan-glossary"><ol>';
    result += glossaryItems;
    result += '</ol>';
    
    for (const [dictName, css] of Object.entries(styles)) {
        const scopedCss = constructDictCss(css, dictName);
        const formatted = scopedCss
        .replace(/\s+/g, ' ')
        .replace(/\s*\{\s*/g, ' { ')
        .replace(/\s*\}\s*/g, ' }\n')
        .replace(/;\s*/g, '; ')
        .trim();
        result += `<style>${formatted}</style>`;
    }
    if (window.compactGlossariesAnki) {
        result += `<style>${COMPACT_GLOSSARIES_ANKI}</style>`;
    }
    result += '</div>';
    return result;
}

function constructFrequencyHtml(frequencies) {
    if (!frequencies || frequencies.length === 0) {
        return '';
    }
    
    let result = '<ul style="text-align: left;">';
    frequencies.forEach(freqGroup => {
        if (!freqGroup?.frequencies?.length) {
            return;
        }
        const dictName = freqGroup.dictionary || '';
        freqGroup.frequencies.forEach(freq => {
            result += `<li>${dictName}: ${freq.displayValue || freq.value}</li>`;
        });
    });
    result += '</ul>';
    return result;
}

function constructPitchPositionHtml(pitches) {
    if (!pitches?.length) {
        return '';
    }
    
    let result = '<ol>';
    pitches.forEach(pitchGroup => {
        pitchGroup.pitchPositions.forEach(pos => {
            result += `<li><span style="display:inline;"><span>[</span><span>${pos}</span><span>]</span></span></li>`;
        });
    });
    result += '</ol>';
    return result;
}

function constructPitchCategories(pitches, reading, rules) {
    if (!pitches?.length) {
        return '';
    }
    
    const verbOrAdj = isVerbOrAdjective(rules);
    const categories = [];
    pitches.forEach(pitchGroup => {
        pitchGroup.pitchPositions.forEach(pos => {
            const category = getPitchCategory(reading, pos, verbOrAdj);
            if (category && !categories.includes(category)) {
                categories.push(category);
            }
        });
    });
    return categories.join(',');
}

// https://github.com/yomidevs/yomitan/blob/d810b2f0842536d24ab82b6cd75d00841710e57b/ext/js/display/structured-content-generator.js#L64
function createDefinitionImage(data, dictionary, exporting = false) {
    const {
        path,
        width = 100,
        height = 100,
        preferredWidth,
        preferredHeight,
        title,
        pixelated,
        imageRendering,
        appearance,
        background,
        collapsed,
        collapsible,
        verticalAlign,
        border,
        borderRadius,
        sizeUnits,
        data: nodeData,
    } = data;
    
    const hasPreferredWidth = (typeof preferredWidth === 'number');
    const hasPreferredHeight = (typeof preferredHeight === 'number');
    const hasDimensions = (hasPreferredWidth || hasPreferredHeight || typeof data.width === 'number' || typeof data.height === 'number');
    const invAspectRatio = (
                            hasPreferredWidth && hasPreferredHeight ?
                            preferredHeight / preferredWidth :
                            height / width
                            );
    const usedWidth = (
                       hasPreferredWidth ?
                       preferredWidth :
                       (hasPreferredHeight ? preferredHeight / invAspectRatio : width)
                       );
    
    const node = document.createElement(exporting ? 'span' : 'a');
    node.classList.add('gloss-image-link');
    if (!exporting) {
        node.target = '_blank';
        node.rel = 'noreferrer noopener';
    }
    
    const imageContainer = document.createElement('span');
    imageContainer.classList.add('gloss-image-container');
    node.appendChild(imageContainer);
    
    const aspectRatioSizer = document.createElement('span');
    aspectRatioSizer.classList.add('gloss-image-sizer');
    imageContainer.appendChild(aspectRatioSizer);
    
    const imageBackground = document.createElement('span');
    imageBackground.classList.add('gloss-image-background');
    imageContainer.appendChild(imageBackground);
    
    const overlay = document.createElement('span');
    overlay.classList.add('gloss-image-container-overlay');
    imageContainer.appendChild(overlay);
    
    node.dataset.path = path;
    node.dataset.dictionary = dictionary;
    node.dataset.hasAspectRatio = 'true';
    node.dataset.imageRendering = typeof imageRendering === 'string' ? imageRendering : (pixelated ? 'pixelated' : 'auto');
    node.dataset.appearance = typeof appearance === 'string' ? appearance : 'auto';
    node.dataset.background = typeof background === 'boolean' ? `${background}` : 'true';
    node.dataset.collapsed = typeof collapsed === 'boolean' ? `${collapsed}` : 'false';
    node.dataset.collapsible = typeof collapsible === 'boolean' ? `${collapsible}` : 'true';
    if (typeof verticalAlign === 'string') {
        node.dataset.verticalAlign = verticalAlign;
    }
    if (typeof sizeUnits === 'string') {
        node.dataset.sizeUnits = sizeUnits;
    }
    
    aspectRatioSizer.style.paddingTop = `${invAspectRatio * 100}%`;
    
    if (typeof border === 'string') { imageContainer.style.border = border; }
    if (typeof borderRadius === 'string') { imageContainer.style.borderRadius = borderRadius; }
    imageContainer.style.width = `${usedWidth}em`;
    if (typeof title === 'string') {
        imageContainer.title = title;
    }
    
    if (!exporting) {
        const imageUrl = `image://?dictionary=${encodeURIComponent(dictionary)}&path=${encodeURIComponent(path)}`;
        if (shouldRenderDefinitionImageToCanvas(path, appearance, usedWidth, invAspectRatio)) {
            imageContainer.appendChild(createDefinitionImageCanvas(imageUrl, nodeData?.alt || title || '', (canvas, sourceImage) => {
                renderDefinitionImageToCanvas(canvas, sourceImage, usedWidth, invAspectRatio, appearance);
            }));
        } else {
            imageContainer.appendChild(createDefinitionImageCanvas(imageUrl, nodeData?.alt || title || '', (canvas, sourceImage) => {
                renderRasterDefinitionImageToCanvas(canvas, sourceImage, imageContainer, aspectRatioSizer, hasDimensions);
            }));
        }
    } else {
        const image = document.createElement('img');
        image.classList.add('gloss-image');
        image.alt = nodeData?.alt || title || '';
        imageContainer.appendChild(image);
    }
    return node;
}

function shouldRenderDefinitionImageToCanvas(path, appearance, usedWidth, invAspectRatio) {
    return /\.svg$/i.test(path) && appearance === 'monochrome' && usedWidth <= 4 && (usedWidth * invAspectRatio) <= 4;
}

function createDefinitionImageCanvas(imageUrl, alt, onLoad) {
    const canvas = document.createElement('canvas');
    canvas.classList.add('gloss-image');
    canvas.setAttribute('role', 'img');
    canvas.setAttribute('aria-label', alt);
    
    const sourceImage = new Image();
    sourceImage.addEventListener('load', () => {
        onLoad(canvas, sourceImage);
    }, {once: true});
    sourceImage.src = imageUrl;
    
    return canvas;
}

function renderDefinitionImageToCanvas(canvas, image, usedWidth, invAspectRatio, appearance) {
    const emSize = Number.parseFloat(getComputedStyle(document.documentElement).fontSize);
    const scaleFactor = Math.ceil(window.devicePixelRatio * 2);
    const pixelWidth = Math.round(usedWidth * emSize * scaleFactor);
    const pixelHeight = Math.round(usedWidth * emSize * invAspectRatio * scaleFactor);
    const maxCanvasSize = 128;
    const scale = Math.min(
                           1,
                           maxCanvasSize / Math.max(pixelWidth, pixelHeight),
                           Math.sqrt((maxCanvasSize * maxCanvasSize) / (pixelWidth * pixelHeight))
                           );
    
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    canvas.width = Math.round(pixelWidth * scale);
    canvas.height = Math.round(pixelHeight * scale);
    
    const context = canvas.getContext('2d');
    if (!context) {
        return;
    }
    
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    
    if (appearance === 'monochrome') {
        context.globalCompositeOperation = 'source-in';
        context.fillStyle = window.matchMedia?.('(prefers-color-scheme: dark)')?.matches ? '#ffffff' : '#000000';
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.globalCompositeOperation = 'source-over';
    }
}

function renderRasterDefinitionImageToCanvas(canvas, image, imageContainer, aspectRatioSizer, hasDimensions) {
    if (!hasDimensions) {
        imageContainer.style.width = `${Math.min(image.naturalWidth, window.innerWidth - 20)}px`;
    }
    
    const invAspectRatio = image.naturalHeight / image.naturalWidth;
    const scaleFactor = Math.ceil(window.devicePixelRatio);
    
    aspectRatioSizer.style.paddingTop = `${invAspectRatio * 100}%`;
    
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    canvas.width = Math.round(imageContainer.clientWidth * scaleFactor);
    canvas.height = Math.round(imageContainer.clientWidth * invAspectRatio * scaleFactor);
    
    const context = canvas.getContext('2d');
    if (!context) {
        return;
    }
    
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
}

// https://github.com/yomidevs/yomitan/blob/c0abb9e98a15aeb6b6f8f6e2d91fe5e54240b54a/ext/js/data/anki-note-data-creator.js#L177-L221
function getFrequencyHarmonicRank(frequencies) {
    if (!frequencies || frequencies.length === 0) {
        return DEFAULT_HARMONIC_RANK;
    }
    
    const values = [];
    const seenDictionaries = new Set();
    frequencies.forEach(freqGroup => {
        const dictionary = freqGroup?.dictionary;
        if (dictionary && seenDictionaries.has(dictionary)) {
            return;
        }
        if (dictionary) {
            seenDictionaries.add(dictionary);
        }
        
        const firstFreq = freqGroup?.frequencies?.[0];
        if (!firstFreq) {
            return;
        }
        
        const displayValue = firstFreq.displayValue;
        if (displayValue != null) {
            const match = String(displayValue).match(/^\d+/);
            if (match) {
                const parsed = Number.parseInt(match[0], 10);
                if (parsed > 0) {
                    values.push(parsed);
                    return;
                }
            }
        }
        
        const val = firstFreq.value;
        if (val && val > 0) {
            values.push(val);
        }
    });
    
    if (values.length === 0) {
        return DEFAULT_HARMONIC_RANK;
    }
    
    const sumOfReciprocals = values.reduce((sum, val) => sum + (1 / val), 0);
    return String(Math.floor(values.length / sumOfReciprocals));
}

async function mineEntry(expression, reading, frequencies, pitches, rules, matched, entryIndex, popupSelectionText) {
    const idx = entryIndex || 0;
    const furiganaPlain = constructFuriganaPlain(expression, reading);
    const glossary = constructGlossaryHtml(idx);
    const freqHarmonicRank = getFrequencyHarmonicRank(frequencies);
    const frequenciesHtml = constructFrequencyHtml(frequencies);
    const singleGlossaries = constructSingleGlossaryHtml(idx);
    const glossaryFirst = Object.values(singleGlossaries)[0] || '';
    const pitchPositions = constructPitchPositionHtml(pitches);
    const pitchCategories = constructPitchCategories(pitches, reading, rules);
    
    if (!audioUrls[idx] && window.audioSources?.length && window.needsAudio) {
        audioUrls[idx] = await fetchAudioUrl(expression, reading || expression);
    }
    
    const audio = audioUrls[idx] || '';
    
    webkit.messageHandlers.mineEntry.postMessage({
        expression,
        reading,
        matched,
        furiganaPlain,
        frequenciesHtml,
        freqHarmonicRank,
        glossary,
        glossaryFirst,
        singleGlossaries: JSON.stringify(singleGlossaries),
        pitchPositions,
        pitchCategories,
        popupSelectionText,
        audio
    });
}

function renderStructuredContent(parent, node, language = null, dictName = null, exporting = false) {
    if (typeof node === 'string') {
        node.split(/\r?\n/).forEach((line, i) => {
            if (i > 0) {
                parent.appendChild(document.createElement('br'));
            }
            if (line) {
                if (!language && !parent.hasAttribute('lang')) {
                    const detected = getLanguageFromText(line, language);
                    if (detected) {
                        parent.setAttribute('lang', detected);
                    }
                }
                parent.appendChild(document.createTextNode(line));
            }
        });
        return;
    }
    
    if (Array.isArray(node)) {
        const isStringArray = node.every(item => typeof item === 'string');
        const insideSpan = parent.tagName === 'SPAN';
        if (isStringArray && node.length > 1 && !insideSpan) {
            const ul = document.createElement('ul');
            ul.classList.add('glossary-list');
            node.forEach(child => {
                const li = document.createElement('li');
                li.appendChild(document.createTextNode(child));
                ul.appendChild(li);
            });
            parent.appendChild(ul);
            return;
        }
        
        const items = node.map(item =>
            item?.type === 'structured-content' ? item.content : item
        );
        const isLinkArray = items.every(item => item?.tag === 'a');
        if (isLinkArray && node.length > 1) {
            const ul = document.createElement('ul');
            ul.classList.add('glossary-list');
            node.forEach(child => {
                const li = document.createElement('li');
                renderStructuredContent(li, child, language, dictName, exporting);
                ul.appendChild(li);
            });
            parent.appendChild(ul);
            return;
        }
        
        node.forEach(child => renderStructuredContent(parent, child, language, dictName, exporting));
        return;
    }
    
    if (!node || typeof node !== 'object') {
        return;
    }
    
    if (node.type === 'structured-content') {
        const container = document.createElement('span');
        container.classList.add('structured-content');
        parent.appendChild(container);
        renderStructuredContent(container, node.content, language, dictName, exporting);
        return;
    }
    
    if (node.tag === 'img') {
        parent.appendChild(createDefinitionImage(node, dictName, exporting));
        return;
    }
    
    const tagName = node.tag || 'span';
    const element = document.createElement(tagName);
    element.classList.add(`gloss-sc-${tagName}`);
    let nextLanguage = language;
    
    if (node.href) {
        element.setAttribute('href', node.href);
        const isExternal = /^https?:\/\//i.test(node.href);
        element.onclick = (e) => {
            e.preventDefault();
            if (isExternal) {
                openExternalLink(node.href);
            } else {
                // TODO: handle redirect to other entry
            }
        };
    }
    
    if (node.title) {
        element.setAttribute('title', node.title);
    }
    
    if (node.lang) {
        element.setAttribute('lang', node.lang);
        nextLanguage = node.lang;
    }
    
    if (node.data) {
        // this is necessary to fix formatting in dicts like daijisen
        for (const [k, v] of Object.entries(node.data)) {
            const isCJK = /^[\u3000-\u9FFF\uF900-\uFAFF]/.test(k);
            element.setAttribute(`data-sc${isCJK ? '' : '-'}${toKebabCase(k)}`, v);
        }
    }
    
    if (node.style) {
        Object.assign(element.style, node.style);
    }
    
    if (node.content) {
        renderStructuredContent(element, node.content, nextLanguage, dictName, exporting);
    }
    
    if (node.colSpan) {
        element.setAttribute('colspan', node.colSpan);
    }
    
    if (node.rowSpan) {
        element.setAttribute('rowspan', node.rowSpan);
    }
    
    if (tagName === 'table') {
        const container = document.createElement('div');
        container.classList.add('gloss-sc-table-container');
        container.appendChild(element);
        parent.appendChild(container);
        return;
    }
    
    parent.appendChild(element);
}

function isPartOfSpeech(tag) {
    return POS_TAGS.has(tag) || tag.startsWith('v5');
}

function parseTags(raw) {
    return (raw || '').split(' ').filter(Boolean);
}

function createGlossaryTags(tags, className = 'glossary-tags') {
    if (!tags?.length) {
        return null;
    }
    return el('div', { className }, tags.map(tag => el('span', { className: 'glossary-tag', textContent: tag })));
}

function createDeinflectionTag(tag) {
    return el('span', {
        className: 'deinflection-tag',
        textContent: tag.name,
        'data-description': tag.description,
        onclick() {
            showDescription(this);
        }
    });
}

function createFrequencyGroup(freqGroup) {
    const values = freqGroup.frequencies.map(f => f.displayValue || f.value).join(', ');
    return el('span', { className: 'frequency-group', 'data-details': freqGroup.dictionary }, [
        el('span', { className: 'frequency-dict-label', textContent: freqGroup.dictionary }),
        el('span', { className: 'frequency-values', textContent: values })
    ]);
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L350
function isMoraPitchHigh(moraIndex, pitchAccentValue) {
    switch (pitchAccentValue) {
        case 0: return (moraIndex > 0);
        case 1: return (moraIndex < 1);
        default: return (moraIndex > 0 && moraIndex < pitchAccentValue);
    }
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L406
function getKanaMorae(text) {
    const morae = [];
    let i;
    for (const c of text) {
        if (SMALL_KANA_SET.has(c) && (i = morae.length) > 0) {
            morae[i - 1] += c;
        } else {
            morae.push(c);
        }
    }
    return morae;
}

// this might be unreliable
function isVerbOrAdjective(rules) {
    return rules?.some(tag => tag.startsWith('v') || tag.startsWith('adj-i')) ?? false;
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L366
function getPitchCategory(reading, pitchAccentValue, verbOrAdjective = false) {
    if (pitchAccentValue === 0) {
        return 'heiban';
    }
    if (verbOrAdjective) {
        return pitchAccentValue > 0 ? 'kifuku' : null;
    }
    if (pitchAccentValue === 1) {
        return 'atamadaka';
    }
    if (pitchAccentValue > 1) {
        const moraCount = getKanaMorae(reading).length;
        return pitchAccentValue >= moraCount ? 'odaka' : 'nakadaka';
    }
    return null;
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/display/pronunciation-generator.js#L38
function createPitchHtml(reading, pitchValue) {
    const morae = getKanaMorae(reading);
    const container = el('span', { className: 'pronunciation-text' });
    
    for (let i = 0; i < morae.length; i++) {
        const mora = morae[i];
        const isHigh = isMoraPitchHigh(i, pitchValue);
        const isHighNext = isMoraPitchHigh(i + 1, pitchValue);
        
        const moraSpan = el('span', {
            className: 'pronunciation-mora',
            'data-pitch': isHigh ? 'high' : 'low',
            'data-pitch-next': isHighNext ? 'high' : 'low',
            textContent: mora
        });
        
        moraSpan.appendChild(el('span', { className: 'pronunciation-mora-line' }));
        container.appendChild(moraSpan);
    }
    
    return container;
}

function createPitchGroup(pitchData, reading) {
    const container = el('div', { className: 'pitch-group', 'data-details': pitchData.dictionary });
    container.appendChild(el('span', { className: 'pitch-dict-label', textContent: pitchData.dictionary }));
    
    const list = el('ul', { className: 'pitch-entries' });
    pitchData.pitchPositions.forEach((pitch) => {
        const li = el('li');
        li.appendChild(createPitchHtml(reading, pitch));
        li.appendChild(document.createTextNode(` [${pitch}]`));
        list.appendChild(li);
    });
    container.appendChild(list);
    
    return container;
}

function createTags(entry) {
    const { deinflectionTrace, frequencies, pitches, reading } = entry;
    const hasDeinflection = deinflectionTrace?.length;
    const hasFrequencies = frequencies?.length;
    const hasPitches = pitches?.length;

    if (!hasDeinflection && !hasFrequencies && !hasPitches) {
        return null;
    }

    const container = el('div', { className: 'entry-tags' });

    if (hasDeinflection) {
        const deinflectionDiv = el('div', { className: 'tag-row' });
        deinflectionTrace.forEach(tag => deinflectionDiv.appendChild(createDeinflectionTag(tag)));
        container.appendChild(deinflectionDiv);
    }

    if (hasFrequencies) {
        const freqContainer = el('div', { className: 'tag-row' });
        frequencies.forEach(freq => freqContainer.appendChild(createFrequencyGroup(freq)));
        container.appendChild(freqContainer);
    }

    if (hasPitches) {
        const pitchContainer = el('div', { className: 'pitch-list' });
        pitches.forEach(pitch => pitchContainer.appendChild(createPitchGroup(pitch, reading)));
        container.appendChild(pitchContainer);
    }

    return container;
}

async function fetchAudioUrl(expression, reading) {
    const templates = window.audioSources;
    if (!templates?.length) return null;
    
    for (const template of templates) {
        const url = template
        .replace('{term}', encodeURIComponent(expression))
        .replace('{reading}', encodeURIComponent(reading));
        try {
            const response = await fetch(`audio://?url=${encodeURIComponent(url)}`);
            const data = await response.json();
            if (data.type === 'audioSourceList' && data.audioSources?.[0]?.url) {
                return data.audioSources[0].url;
            }
        } catch {}
    }
    return null;
}

function playWordAudio(audioUrl) {
    const playHandler = window.webkit?.messageHandlers?.playWordAudio;
    if (!playHandler) {
        return false;
    }
    
    try {
        playHandler.postMessage({
            url: audioUrl,
            mode: window.audioPlaybackMode || 'interrupt'
        });
        return true;
    } catch {
        return false;
    }
}

function showAudioError(button) {
    button.textContent = '✕';
    setTimeout(() => {
        button.textContent = '♪';
    }, 1500);
}

function createAudioButton(expression, reading, entryIndex) {
    const button = el('button', {
        className: 'audio-button',
        textContent: '♪',
        onclick: async () => {
            if (!audioUrls[entryIndex]) {
                audioUrls[entryIndex] = await fetchAudioUrl(expression, reading);
            }
            if (!audioUrls[entryIndex]) {
                showAudioError(button);
                return;
            }
            if (!playWordAudio(audioUrls[entryIndex])) {
                showAudioError(button);
            }
        }
    });
    return button;
}

async function createEntryHeader(entry, idx) {
    const { expression, reading, matched, frequencies, pitches, rules } = entry;
    const header = el('div', { className: 'entry-header' });
    
    const expressionSpan = el('span', { className: 'expression' });
    let needsScroll = false;
    if (reading && reading !== expression) {
        needsScroll = buildFuriganaEl(expressionSpan, expression, reading);
    } else {
        expressionSpan.textContent = expression;
    }
    if (needsScroll) {
        const expressionScroll = el('div', { className: 'expression-scroll' });
        expressionScroll.appendChild(expressionSpan);
        header.appendChild(expressionScroll);
    } else {
        header.appendChild(expressionSpan);
    }
    
    const buttonsContainer = el('div', { className: 'header-buttons' });
    
    if (window.audioSources?.length) {
        buttonsContainer.appendChild(createAudioButton(expression, reading, idx));
    }
    
    const isDuplicate = await webkit.messageHandlers.duplicateCheck.postMessage(expression);
    const mineButton = el('button', {
        className: 'mine-button' + (isDuplicate ? ' duplicate' : '') + (isDuplicate && !window.allowDupes ? ' disabled' : ''),
        textContent: isDuplicate ? '✓' : '+',
        disabled: isDuplicate && !window.allowDupes,
        ontouchstart: () => {
            lastSelection = window.getSelection()?.toString() || '';
        },
        onclick: async () => {
            await mineEntry(expression, reading, frequencies, pitches, rules, matched, idx, lastSelection);
            setTimeout(async () => {
                const wasAdded = await webkit.messageHandlers.duplicateCheck.postMessage(expression);
                if (wasAdded) {
                    mineButton.textContent = '✓';
                    mineButton.classList.add('duplicate');
                    if (!window.allowDupes) {
                        mineButton.classList.add('disabled');
                        mineButton.disabled = true;
                    }
                }
            }, 1500);
        }
    });
    buttonsContainer.appendChild(mineButton);
    
    header.appendChild(buttonsContainer);
    
    return header;
}

function createGlossarySection(dictName, contents, isFirst) {
    const details = el('details', { className: 'glossary-group' });
    if (!window.collapseDictionaries || isFirst) {
        details.open = true;
    }
    
    const summary = el('summary', { className: 'dict-label' });
    summary.appendChild(el('span', { className: 'dict-name', textContent: dictName }));
    details.appendChild(summary);
    
    const dictWrapper = document.createElement('div');
    dictWrapper.setAttribute('data-dictionary', dictName);
    const compactCss = window.compactGlossaries ? `
        ul[data-sc-content="glossary"],
        ol[data-sc-content="glossary"],
        .glossary-list {
            list-style: none;
            padding-left: 0;
            margin: 0;
        }
        ul[data-sc-content="glossary"] > li,
        ol[data-sc-content="glossary"] > li,
        .glossary-list > li {
            display: inline;
        }
        ul[data-sc-content="glossary"] > li::after,
        ol[data-sc-content="glossary"] > li::after,
        .glossary-list > li::after {
            content: " | ";
            opacity: 0.6;
        }
        ul[data-sc-content="glossary"] > li:last-child::after,
        ol[data-sc-content="glossary"] > li:last-child::after,
        .glossary-list > li:last-child::after {
            content: "";
        }
    ` : '';
    
    const dictStyle = window.dictionaryStyles?.[dictName] ?? '';
    dictWrapper.appendChild(el('style', {
        textContent: `
            [data-dictionary="${dictName}"] {
                @media (prefers-color-scheme: light) { color: #000; }
                @media (prefers-color-scheme: dark) { color: #fff; }
                ${dictStyle}
                ${compactCss}
            }
        `.trim()
    }));
    
    const termTags = [...new Set(parseTags(contents[0]?.termTags))];
    const renderContent = (parent, content) => {
        try {
            renderStructuredContent(parent, JSON.parse(content), null, dictName);
        } catch {
            renderStructuredContent(parent, content, null, dictName);
        }
    };
    
    const termTagsRow = createGlossaryTags(termTags);
    if (termTagsRow) {
        dictWrapper.appendChild(termTagsRow);
    }
    
    if (contents.length > 1) {
        const ol = el('ol');
        let prevTags = null;
        contents.forEach((item) => {
            const li = el('li');
            const parsedTags = parseTags(item.definitionTags).filter(tag => !NUMERIC_TAG.test(tag));
            const posTags = [...new Set(parsedTags.filter(isPartOfSpeech))].sort();
            const currentTags = JSON.stringify(posTags);
            const filteredTags = parsedTags.filter(tag => !isPartOfSpeech(tag) || !(prevTags !== null && prevTags === currentTags));
            const tags = createGlossaryTags(filteredTags);
            if (tags) {
                li.appendChild(tags);
            }
            const content = el('div', { className: 'glossary-content' });
            renderContent(content, item.content);
            li.appendChild(content);
            ol.appendChild(li);
            prevTags = currentTags;
        });
        dictWrapper.appendChild(ol);
    } else {
        contents.forEach((item, idx) => {
            const wrapper = el('div');
            const tags = createGlossaryTags(parseTags(item.definitionTags).filter(tag => !NUMERIC_TAG.test(tag)));
            if (tags) {
                wrapper.appendChild(tags);
            }
            const content = el('div', { className: 'glossary-content' });
            renderContent(content, item.content);
            wrapper.appendChild(content);
            dictWrapper.appendChild(wrapper);
        });
    }
    
    details.appendChild(dictWrapper);
    return details;
}

window.renderPopup = function() {
    const container = document.getElementById('entries-container');
    if (!window.entryCount) {
        return;
    }
    
    (async () => {
        for (let idx = 0; idx < window.entryCount; idx++) {
            const entry = await webkit.messageHandlers.getEntry.postMessage(idx);
            if (!entry) continue;
            
            window.lookupEntries ??= [];
            window.lookupEntries[idx] = entry;
            
            if (idx > 0) {
                container.appendChild(document.createElement('hr'));
            }
            
            const entryDiv = el('div', { className: 'entry' });
            entryDiv.appendChild(await createEntryHeader(entry, idx));
            
            if (window.audioEnableAutoplay && window.audioSources?.length && idx == 0) {
                setTimeout(() => {
                    const audioButton = entryDiv.querySelector('.audio-button');
                    if (audioButton) {
                        audioButton.click();
                    }
                }, 70);
            }
            
            const tags = createTags(entry);
            if (tags) {
                entryDiv.appendChild(tags);
            }
            
            container.appendChild(entryDiv);
            await new Promise(r => requestAnimationFrame(r));
            
            const grouped = {};
            entry.glossaries.forEach(g => {
                (grouped[g.dictionary] ??= []).push({
                    content: g.content,
                    definitionTags: g.definitionTags,
                    termTags: g.termTags
                });
            });
            
            const dictNames = Object.keys(grouped);
            for (let dictIdx = 0; dictIdx < dictNames.length; dictIdx++) {
                entryDiv.appendChild(createGlossarySection(dictNames[dictIdx], grouped[dictNames[dictIdx]], dictIdx === 0));
                await new Promise(r => requestAnimationFrame(r));
            }
        }
    })();
    
    if (window.customCSS) {
        const customStyle = document.createElement('style');
        customStyle.textContent = window.customCSS;
        document.body.appendChild(customStyle);
    }
    
    container.addEventListener('click', (e) => {
        const target = e.target?.nodeType === Node.TEXT_NODE ? e.target.parentElement : e.target;
        if (!target?.closest('.glossary-content')) {
            webkit.messageHandlers.tapOutside.postMessage(null);
            return;
        }
        const selected = window.hoshiSelection?.selectText(e.clientX, e.clientY, 16);
        if (!selected) {
            webkit.messageHandlers.tapOutside.postMessage(null);
            return;
        }
    });
};
