//
//  popup.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  Copyright © 2023-2025 Yomitan Authors.
//  Copyright © 2021-2022 Yomichan Authors.
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  Based on: https://github.com/Manhhao/Hoshi-Reader/blob/ff31274acf44683e5b61abdfb2a273fc738d4711/Features/Popup/popup.js
//  Modified for use in Aidoku
//

const KANJI_RANGE = '\u4E00-\u9FFF\u3400-\u4DBF\uF900-\uFAFF\u3005';
const KANJI_PATTERN = new RegExp(`[${KANJI_RANGE}]`);
const KANJI_SEGMENT_PATTERN = new RegExp(`[${KANJI_RANGE}]+|[^${KANJI_RANGE}]+`, 'g');
const KANA_PATTERN = /[\u3040-\u30FF\uFF66-\uFF9F]/;
const DEFAULT_HARMONIC_RANK = '9999999';
const SMALL_KANA_SET = new Set('ぁぃぅぇぉゃゅょゎァィゥェォャュョヮ');
const NUMERIC_TAG = /^\d+$/;
// this might not cover every tag
const POS_TAGS = new Set(['n', 'adj-i', 'adj-na', 'adj-no', 'v1', 'vk', 'vs', 'vs-i', 'vs-s', 'vz', 'vi', 'vt']);
let audioUrls = {};
let lastSelection = '';
let currentDictionaryMedia = null;
let selectedDictionaries = {};

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
function isStringPartiallyJapanese(str) {
    if (str.length === 0) { return false; }
    for (const c of str) {
        if (window.hoshiSelection?.isCodePointJapanese(c.codePointAt(0))) {
            return true;
        }
    }
    return false;
}

// https://github.com/yomidevs/yomitan/blob/c0abb9e98a15aeb6b6f8f6e2d91fe5e54240b54a/ext/js/language/zh/chinese.js#L54
function isStringPartiallyChinese(text) {
    if (!text) {
        return false;
    }
    return KANJI_PATTERN.test(text) || /[\u3100-\u312F\u31A0-\u31BF]/.test(text);
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

function applyTableStyles(html) {
    const tableStyle = 'table-layout:auto;border-collapse:collapse;';
    const cellStyle = 'border-style:solid;padding:0.25em;vertical-align:top;border-width:1px;border-color:currentColor;';
    const thStyle = 'font-weight:bold;' + cellStyle;

    return html
    .replace(/<table(?=[>\s])/g, `<table style="${tableStyle}"`)
    .replace(/<th(?=[>\s])/g, `<th style="${thStyle}"`)
    .replace(/<td(?=[>\s])/g, `<td style="${cellStyle}"`);
}

function applyImageStyles(node, imageContainer, aspectRatioSizer, imageBackground, image, filename, appearance, useEmUnits) {
    // .gloss-image-link
    node.style.cssText += 'display:inline-block;position:relative;line-height:1;max-width:100%;';
    // .gloss-image-container
    imageContainer.style.cssText += `display:inline-block;white-space:nowrap;max-width:100%;max-height:100vh;position:relative;vertical-align:top;line-height:0;overflow:hidden;font-size:${useEmUnits ? '1em' : '1px'};`;
    // .gloss-image-link[data-has-aspect-ratio=true] .gloss-image-sizer
    aspectRatioSizer.style.cssText += 'display:inline-block;width:0;vertical-align:top;font-size:0;';
    // .gloss-image-link[data-has-aspect-ratio=true] .gloss-image
    image.style.cssText += 'display:inline-block;vertical-align:top;object-fit:contain;border:none;outline:none;position:absolute;left:0;top:0;width:100%;height:100%;';
    // .gloss-image-background, set image url directly
    if (appearance === 'monochrome') {
        imageBackground.style.cssText += `--image:url("${filename}");position:absolute;left:0;top:0;width:100%;height:100%;-webkit-mask-repeat:no-repeat;-webkit-mask-position:center center;-webkit-mask-mode:alpha;-webkit-mask-size:contain;-webkit-mask-image:var(--image);mask-repeat:no-repeat;mask-position:center center;mask-mode:alpha;mask-size:contain;mask-image:var(--image);background-color:currentColor;`;
        image.style.opacity = '0';
    }
}

function getMediaFilename(dictionary, path) {
    const key = `${dictionary}\n${path}`;
    if (!currentDictionaryMedia.has(key)) {
        const extension = path.split('.').pop();
        currentDictionaryMedia.set(key, {
            dictionary,
            path,
            filename: `hoshi_dict_${currentDictionaryMedia.size}.${extension}`,
        });
    }
    return currentDictionaryMedia.get(key).filename;
}

function setStructuredContentElementStyle(element, style) {
    for (const [property, value] of Object.entries(style)) {
        if ((property === 'marginTop' || property === 'marginLeft' || property === 'marginRight' || property === 'marginBottom') && typeof value === 'number') {
            element.style[property] = `${value}em`;
        } else {
            element.style[property] = value;
        }
    }
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
        let label = '';
        if (dictChanged) {
            label = tags ? `(${tags}, ${dictName})` : `(${dictName})`;
        } else {
            label = tags ? `(${tags})` : '';
        }
        currentGlossary += `<li data-dictionary="${dictName}"><i>${label}</i> <span>${content}</span></li>`;
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
        if (window.excludedDictionaries.includes(dictName)) {
            return;
        }

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

        const content = applyTableStyles(tempDiv.innerHTML);
        glossaryItems += `<li data-dictionary="${dictName}"><i>${label}</i> <span>${content}</span></li>`;
        prevTags = currentTags;

        const css = window.dictionaryStyles?.[dictName];
        if (css && !styles[dictName]) {
            styles[dictName] = css;
        }
    });

    let stylesHtml = '';
    for (const [dictName, css] of Object.entries(styles)) {
        const scopedCss = constructDictCss(css, dictName);
        const formatted = scopedCss
        .replace(/\s+/g, ' ')
        .replace(/\s*\{\s*/g, ' { ')
        .replace(/\s*\}\s*/g, ' }\n')
        .replace(/;\s*/g, '; ')
        .trim();
        stylesHtml += `<style>${formatted}</style>`;
    }
    if (window.compactGlossariesAnki) {
        stylesHtml += `<style>${COMPACT_GLOSSARIES_ANKI}</style>`;
    }

    return `<div style="text-align: left;" class="yomitan-glossary"><ol>${glossaryItems}</ol>${stylesHtml}</div>`;
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

function constructPitchAccentGraphsHtml(pitches, reading) {
    if (!pitches?.length) {
        return '';
    }

    const morae = getKanaMorae(reading);
    const seen = new Set();
    const graphs = [];
    pitches.forEach(pitchGroup => {
        pitchGroup.pitchPositions.forEach(pos => {
            if (window.deduplicatePitchAccents) {
                if (seen.has(pos)) {
                    return;
                }
                seen.add(pos);
            }
            graphs.push(createPronunciationGraph(morae, pos).outerHTML);
        });
    });

    if (graphs.length === 0) {
        return '';
    }
    if (graphs.length === 1) {
        return graphs[0];
    }
    return `<ol>${graphs.map(g => `<li>${g}</li>`).join('')}</ol>`;
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
            const img = document.createElement('img');
            img.classList.add('gloss-image');
            img.alt = nodeData?.alt || title || '';
            if (!hasDimensions) {
                img.addEventListener('load', () => {
                    imageContainer.style.width = `${Math.min(img.naturalWidth, window.innerWidth - 20)}px`;
                    aspectRatioSizer.style.paddingTop = `${(img.naturalHeight / img.naturalWidth) * 100}%`;
                }, {once: true});
            } else if (!hasPreferredWidth && !hasPreferredHeight && sizeUnits === 'em') {
                img.addEventListener('load', () => {
                    const aspectRatio = img.naturalHeight / img.naturalWidth;
                    const widthEm = typeof data.width === 'number' ? data.width : data.height / aspectRatio;
                    imageContainer.style.width = `${widthEm}em`;
                    aspectRatioSizer.style.paddingTop = `${aspectRatio * 100}%`;
                }, {once: true});
            }
            img.src = imageUrl;
            imageContainer.appendChild(img);
        }
    } else {
        const alt = nodeData?.alt || title || '';
        const filename = (window.useAnkiConnect || window.embedMedia) ? getMediaFilename(dictionary, path) : null;
        const image = document.createElement(filename ? 'img' : 'span');
        image.classList.add('gloss-image');
        if (filename) {
            image.alt = alt;
            image.src = filename;
            if (sizeUnits === 'em') {
                const emSize = 14;
                const scaleFactor = 2 * window.devicePixelRatio;
                image.width = usedWidth * emSize * scaleFactor;
            } else {
                image.width = usedWidth;
            }
            image.height = image.width * invAspectRatio;
            applyImageStyles(node, imageContainer, aspectRatioSizer, imageBackground, image, filename, appearance, sizeUnits === 'em');
        } else {
            image.textContent = alt;
        }
        imageContainer.appendChild(image);
    }
    return node;
}

// ai slop
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
    const maxCanvasSize = 256;
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

async function mineEntry(expression, reading, frequencies, pitches, rules, matched, entryIndex, popupSelectionText, slotIndex) {
    const idx = entryIndex || 0;
    const furiganaPlain = constructFuriganaPlain(expression, reading);
    currentDictionaryMedia = new Map();
    const glossary = constructGlossaryHtml(idx);
    const freqHarmonicRank = getFrequencyHarmonicRank(frequencies);
    const frequenciesHtml = constructFrequencyHtml(frequencies);
    const singleGlossaries = constructSingleGlossaryHtml(idx);
    const dictionaryMedia = currentDictionaryMedia;
    currentDictionaryMedia = null;
    const pitchPositions = constructPitchPositionHtml(pitches);
    const pitchCategories = constructPitchCategories(pitches, reading, rules);
    const pitchAccentGraphs = constructPitchAccentGraphsHtml(pitches, reading);

    if (!audioUrls[idx] && window.audioSources?.length && window.needsAudio) {
        audioUrls[idx] = await fetchAudioUrl(expression, reading || expression);
    }

    const audio = audioUrls[idx] || '';

    return await webkit.messageHandlers.mineEntry.postMessage({
        expression,
        reading,
        matched,
        furiganaPlain,
        frequenciesHtml,
        freqHarmonicRank,
        glossary,
        singleGlossaries: JSON.stringify(singleGlossaries),
        pitchPositions,
        pitchCategories,
        pitchAccentGraphs,
        popupSelectionText,
        audio,
        slotIndex: String(slotIndex),
        selectedDictionary: selectedDictionaries[idx]?.name || '',
        dictionaryMedia: JSON.stringify([...dictionaryMedia.values()])
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
        element.onclick = async (e) => {
            e.preventDefault();
            e.stopPropagation();
            if (isExternal) {
                openExternalLink(node.href);
            } else {
                const i = node.href.indexOf('?');
                const query = i < 0 ? null : new URLSearchParams(node.href.slice(i + 1)).get('query');
                const count = query ? await webkit.messageHandlers.lookupRedirect.postMessage(query) : 0;
                if (count > 0) {
                    redirect(count);
                }
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
        setStructuredContentElementStyle(element, node.style);
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
        el('span', { className: 'frequency-dict-label' }, [
            el('span', { className: 'frequency-dict-label-text', textContent: freqGroup.dictionary })
        ]),
        el('span', { className: 'frequency-values', textContent: values })
    ]);
}

function createHarmonicFrequencyTag(frequencies) {
    const rank = getFrequencyHarmonicRank(frequencies);
    return el('span', { className: 'frequency-group harmonic-frequency' }, [
        el('span', { className: 'frequency-dict-label' }, [
            el('span', { className: 'frequency-dict-label-text', textContent: 'Average' })
        ]),
        el('span', { className: 'frequency-values', textContent: rank })
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

// https://github.com/yomidevs/yomitan/blob/d9c3c4d09e6ccf62f4e0fa3cd32abef17b5b4084/ext/js/display/pronunciation-generator.js#L115
// https://github.com/yomidevs/yomitan/blob/d9c3c4d09e6ccf62f4e0fa3cd32abef17b5b4084/ext/css/display-pronunciation.css#L101
function createPronunciationGraph(morae, pitchPositions) {
    const ii = morae.length;

    const svgns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(svgns, 'svg');
    svg.setAttribute('xmlns', svgns);
    //
    svg.setAttribute('style', 'display:inline-block;vertical-align:middle;height:1.5em;');
    svg.setAttribute('focusable', 'false');
    svg.setAttribute('viewBox', `0 0 ${50 * (ii + 1)} 100`);

    if (ii <= 0) { return svg; }

    // https://github.com/yomidevs/yomitan/blob/d9c3c4d09e6ccf62f4e0fa3cd32abef17b5b4084/ext/js/display/pronunciation-generator.js#L317
    const createGraphCircle = (style, x, y, radius) => {
        const node = document.createElementNS(svgns, 'circle');
        node.setAttribute('style', style);
        node.setAttribute('cx', `${x}`);
        node.setAttribute('cy', `${y}`);
        node.setAttribute('r', radius);
        return node;
    };

    // https://github.com/yomidevs/yomitan/blob/d9c3c4d09e6ccf62f4e0fa3cd32abef17b5b4084/ext/js/display/pronunciation-generator.js#L290
    const addGraphDot = (x, y) => {
        // pronunciation-graph-dot
        svg.appendChild(createGraphCircle('stroke-width:5;fill:currentColor;stroke:currentColor;', x, y, '15'));
    };

    // https://github.com/yomidevs/yomitan/blob/d9c3c4d09e6ccf62f4e0fa3cd32abef17b5b4084/ext/js/display/pronunciation-generator.js#L290
    const addGraphDotDownstep = (x, y) => {
        // pronunciation-graph-dot-downstep1
        svg.appendChild(createGraphCircle('fill:none;stroke-width:5;stroke:currentColor;', x, y, '15'));
        // pronunciation-graph-dot-downstep2
        svg.appendChild(createGraphCircle('fill:currentColor;', x, y, '5'));
    };

    // https://github.com/yomidevs/yomitan/blob/d9c3c4d09e6ccf62f4e0fa3cd32abef17b5b4084/ext/js/display/pronunciation-generator.js#L301
    const addGraphTriangle = (x, y) => {
        const node = document.createElementNS(svgns, 'path');
        // pronunciation-graph-triangle
        node.setAttribute('style', 'fill:none;stroke-width:5;stroke:currentColor;');
        node.setAttribute('d', 'M0 13 L15 -13 L-15 -13 Z');
        node.setAttribute('transform', `translate(${x},${y})`);
        svg.appendChild(node);
    };

    const path1 = document.createElementNS(svgns, 'path');
    svg.appendChild(path1);

    const path2 = document.createElementNS(svgns, 'path');
    svg.appendChild(path2);

    const pathPoints = [];
    for (let i = 0; i < ii; ++i) {
        const highPitch = isMoraPitchHigh(i, pitchPositions);
        const highPitchNext = isMoraPitchHigh(i + 1, pitchPositions);
        const x = i * 50 + 25;
        const y = highPitch ? 25 : 75;
        if (highPitch && !highPitchNext) {
            addGraphDotDownstep(x, y);
        } else {
            addGraphDot(x, y);
        }
        pathPoints.push(`${x} ${y}`);
    }

    // pronunciation-graph-line
    path1.setAttribute('style', 'fill:none;stroke-width:5;stroke:currentColor;');
    path1.setAttribute('d', `M${pathPoints.join(' L')}`);

    pathPoints.splice(0, ii - 1);
    {
        const highPitch = isMoraPitchHigh(ii, pitchPositions);
        const x = ii * 50 + 25;
        const y = highPitch ? 25 : 75;
        addGraphTriangle(x, y);
        pathPoints.push(`${x} ${y}`);
    }

    // pronunciation-graph-line-tail
    path2.setAttribute('style', 'fill:none;stroke-width:5;stroke:currentColor;stroke-dasharray:5 5;');
    path2.setAttribute('d', `M${pathPoints.join(' L')}`);

    return svg;
}

function createPitchGroup(pitchData, reading) {
    const container = el('div', { className: 'pitch-group', 'data-details': pitchData.dictionary });
    container.appendChild(el('span', { className: 'pitch-dict-label' }, [
        el('span', { className: 'pitch-dict-label-text', textContent: pitchData.dictionary })
    ]));

    const list = el('ul', { className: 'pitch-entries' });
    pitchData.pitchPositions.forEach((pitch) => {
        const li = el('li');
        li.appendChild(createPitchHtml(reading, pitch));
        li.appendChild(document.createTextNode(` [${pitch}]`));
        list.appendChild(li);
    });
    pitchData.transcriptions.forEach((transcription) => {
        const li = el('li');
        li.appendChild(document.createTextNode(transcription));
        list.appendChild(li);
    });
    container.appendChild(list);

    return container;
}

function createTags(entry) {
    const { deinflectionTrace, frequencies, pitches, reading, expression } = entry;
    const hasDeinflection = deinflectionTrace?.length;
    const hasFrequencies = frequencies?.length;
    const hasPitches = pitches?.length;

    if (!hasDeinflection && !hasFrequencies && !hasPitches && !window.showExpressionTags) {
        return null;
    }

    const container = el('div', { className: 'entry-tags' });

    if (window.showExpressionTags) {
        const exprRow = el('div', { className: 'tag-row expr-tag-row' });
        exprRow.appendChild(el('span', { className: 'expr-tag', textContent: expression }));
        if (reading && reading !== expression) {
            exprRow.appendChild(el('span', { className: 'expr-tag', textContent: reading }));
        }
        container.appendChild(exprRow);
    }

    if (hasDeinflection) {
        const deinflectionDiv = el('div', { className: 'tag-row' });
        deinflectionTrace.forEach(tag => deinflectionDiv.appendChild(createDeinflectionTag(tag)));
        container.appendChild(deinflectionDiv);
    }

    if (hasFrequencies) {
        if (window.harmonicFrequency) {
            const normalRow = el('div', { className: 'tag-row', style: 'display:none' });
            frequencies.forEach(freq => normalRow.appendChild(createFrequencyGroup(freq)));

            const harmonicRow = el('div', { className: 'tag-row' });
            harmonicRow.appendChild(createHarmonicFrequencyTag(frequencies));

            const toggle = () => {
                const swap = harmonicRow.style.display !== 'none';
                harmonicRow.style.display = swap ? 'none' : '';
                normalRow.style.display = swap ? '' : 'none';
                requestAnimationFrame(reportButtonRects);
            };

            normalRow.addEventListener('click', toggle);
            harmonicRow.addEventListener('click', toggle);
            container.appendChild(harmonicRow);
            container.appendChild(normalRow);
        } else {
            const freqContainer = el('div', { className: 'tag-row' });
            frequencies.forEach(freq => freqContainer.appendChild(createFrequencyGroup(freq)));
            container.appendChild(freqContainer);
        }
    }

    if (hasPitches) {
        const pitchContainer = el('div', { className: 'pitch-list' });
        if (window.deduplicatePitchAccents) {
            const seen = new Set();
            pitches.forEach(pitch => {
                const unique = pitch.pitchPositions.filter(pos => !seen.has(pos));
                const transcriptions = pitch.transcriptions;
                if (unique.length > 0 || transcriptions.length > 0) {
                    unique.forEach(pos => seen.add(pos));
                    pitchContainer.appendChild(createPitchGroup({ dictionary: pitch.dictionary, pitchPositions: unique, transcriptions }, reading));
                }
            });
        } else {
            pitches.forEach(pitch => pitchContainer.appendChild(createPitchGroup(pitch, reading)));
        }
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

function reportButtonRects() {
    const rects = [...document.querySelectorAll('.button-slot:not([hidden])')].map(slot => {
        const rect = slot.getBoundingClientRect();
        return {
            kind: slot.dataset.kind,
            entryIndex: Number(slot.dataset.entryIndex),
            slotIndex: Number(slot.dataset.slotIndex),
            x: rect.left + window.scrollX,
            y: rect.top + window.scrollY,
            width: rect.width,
            height: rect.height,
            state: slot.dataset.state || 'default',
            enabled: slot.dataset.enabled !== 'false'
        };
    });
    webkit.messageHandlers.buttonRects.postMessage(rects);
}

function createButtonSlot(kind, entryIndex, slotIndex, enabled = true, hidden = false) {
    return el('span', {
        className: 'button-slot',
        hidden,
        'data-kind': kind,
        'data-entry-index': entryIndex,
        'data-slot-index': slotIndex,
        'data-enabled': String(enabled)
    });
}

function getButtonSlot(kind, entryIndex, slotIndex) {
    return document.querySelector(`.button-slot[data-kind="${kind}"][data-entry-index="${entryIndex}"][data-slot-index="${slotIndex}"]`);
}

function getButtonSlots(kind, entryIndex) {
    return [...document.querySelectorAll(`.button-slot[data-kind="${kind}"][data-entry-index="${entryIndex}"]`)];
}

function updateButtonSlot(slot, changes) {
    if (!slot || !slot.isConnected) { return; }
    if ('state' in changes) { slot.dataset.state = changes.state; }
    if ('enabled' in changes) { slot.dataset.enabled = String(changes.enabled); }
    if ('hidden' in changes) { slot.hidden = changes.hidden; }
    requestAnimationFrame(reportButtonRects);
}

async function playEntryAudio(entryIndex) {
    const entry = window.lookupEntries?.[entryIndex];
    if (!entry) { return; }
    const audioSlot = getButtonSlots('audio', entryIndex)[0];

    if (!audioUrls[entryIndex]) {
        audioUrls[entryIndex] = await fetchAudioUrl(entry.expression, entry.reading);
    }
    if (!audioUrls[entryIndex] || !playWordAudio(audioUrls[entryIndex])) {
        updateButtonSlot(audioSlot, { state: 'error' });
        setTimeout(() => updateButtonSlot(audioSlot, { state: 'default' }), 1500);
    }
}

async function checkDuplicates(entryIndex) {
    const entry = window.lookupEntries?.[entryIndex];
    if (!entry) {
        return;
    }

    if (window.useAnkiConnect && !window.isAnkiConnectReachable) {
        getButtonSlots('mine', entryIndex).forEach(slot => {
            updateButtonSlot(slot, { state: 'default', enabled: false });
            updateButtonSlot(getButtonSlot('note', entryIndex, Number(slot.dataset.slotIndex)), { hidden: true });
        });
        return;
    }

    const results = await webkit.messageHandlers.duplicateCheck.postMessage({
        '{expression}': entry.expression,
        '{reading}': entry.reading
    });
    getButtonSlots('mine', entryIndex).forEach(slot => {
        const i = Number(slot.dataset.slotIndex);
        const isDuplicate = results?.[i] === true;
        const isValidFormat = window.validFormatFlags[i];
        updateButtonSlot(slot, {
            state: isDuplicate ? 'duplicate' : 'default',
            enabled: isValidFormat && !(isDuplicate && !window.allowDupes)
        });
        updateButtonSlot(getButtonSlot('note', entryIndex, i), {
            hidden: !isDuplicate || window.disableShowNotes
        });
    });
}

function recheckDuplicates() {
    const indices = new Set(
        [...document.querySelectorAll('.button-slot[data-kind="mine"]')]
            .map(slot => Number(slot.dataset.entryIndex))
    );
    indices.forEach(checkDuplicates);
}

async function mineEntryAtIndex(entryIndex, slotIndex) {
    const entry = window.lookupEntries?.[entryIndex];
    if (!entry) { return; }
    const { expression, reading, frequencies, pitches, rules, matched } = entry;

    lastSelection = window.getSelection()?.toString() || '';
    getButtonSlots('mine', entryIndex).forEach(slot => updateButtonSlot(slot, { enabled: false }));

    await mineEntry(expression, reading, frequencies, pitches, rules, matched, entryIndex, lastSelection, slotIndex);
    await checkDuplicates(entryIndex);
}

function showNotesAtIndex(entryIndex, slotIndex) {
    const entry = window.lookupEntries?.[entryIndex];
    if (!entry) { return; }
    webkit.messageHandlers.showNotes.postMessage({
        '{expression}': entry.expression,
        '{reading}': entry.reading,
        slotIndex: String(slotIndex)
    });
}

function createEntryHeader(entry, idx) {
    const { expression, reading } = entry;
    const header = el('div', { className: 'entry-header' });

    const expressionSpan = el('span', { className: 'expression' });
    let needsScroll = false;
    if (reading && reading !== expression) {
        needsScroll = buildFuriganaEl(expressionSpan, expression, reading);
    } else {
        expressionSpan.textContent = expression;
    }

    // empty placeholder to reserve space even when no ruby is present
    if (!expressionSpan.querySelector('rt')) {
        const zwsp = String.fromCharCode(0x200b);
        expressionSpan.appendChild(el('ruby', {}, [zwsp, el('rt', { className: 'hidden', textContent: zwsp })]));
    }

    const buttonsContainer = el('div', { className: 'header-buttons' });
    for (let slotIndex = 0; slotIndex < window.cardFormatCount; slotIndex++) {
        const mineSlot = createButtonSlot('mine', idx, slotIndex, false);
        const noteSlot = createButtonSlot('note', idx, slotIndex, true, true);
        if (slotIndex === 0) {
            buttonsContainer.appendChild(noteSlot);
            buttonsContainer.appendChild(mineSlot);
        } else {
            noteSlot.dataset.placement = 'above';
            mineSlot.appendChild(noteSlot);
            buttonsContainer.appendChild(mineSlot);
        }
    }
    checkDuplicates(idx);

    if (window.audioSources?.length) {
        buttonsContainer.appendChild(createButtonSlot('audio', idx, null));
    }

    header.appendChild(buttonsContainer);
    requestAnimationFrame(reportButtonRects);
    if (needsScroll) {
        const expressionScroll = el('div', { className: 'expression-scroll' });
        expressionScroll.appendChild(expressionSpan);
        header.appendChild(expressionScroll);
    } else {
        header.appendChild(expressionSpan);
    }

    return header;
}

function createGlossarySection(dictName, contents, isFirst, entryIdx) {
    const details = el('details', { className: 'glossary-group', 'data-dictionary': dictName });
    const collapsed = window.collapseMode === 'Collapse All'
    || (window.collapseMode === 'Custom' && window.collapsedDictionaries.includes(dictName));
    details.open = !collapsed || (window.expandFirstDictionary && isFirst);

    const summary = el('summary', { className: 'dict-label' });
    summary.appendChild(el('span', { className: 'dict-name', textContent: dictName }));
    let timer = null, longPressed = false;
    const toggleSelection = () => {
        longPressed = true;
        const selected = selectedDictionaries[entryIdx];
        selected?.label.classList.remove('selected');
        if (selected?.name === dictName) {
            delete selectedDictionaries[entryIdx];
        } else {
            selectedDictionaries[entryIdx] = { name: dictName, label: summary };
            summary.classList.add('selected');
        }
    };
    summary.addEventListener('pointerdown', () => {
        longPressed = false;
        timer = setTimeout(toggleSelection, 400);
    });
    const cancel = () => { clearTimeout(timer); };
    summary.addEventListener('pointerup', cancel);
    summary.addEventListener('pointercancel', cancel);
    summary.addEventListener('click', (e) => { if (longPressed) e.preventDefault(); });
    details.appendChild(summary);

    const dictWrapper = document.createElement('div');
    dictWrapper.setAttribute('data-dictionary', dictName);

    const dictStyle = window.dictionaryStyles?.[dictName] ?? '';
    dictWrapper.appendChild(el('style', {
        textContent: `
            [data-dictionary="${dictName}"] {
                @media (prefers-color-scheme: light) { color: #000; }
                @media (prefers-color-scheme: dark) { color: #fff; }
                ${dictStyle}
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
        contents.forEach((item) => {
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

const backStack = [];
const forwardStack = [];

function redirect(count) {
    backStack.push(snapshot());
    forwardStack.length = 0;
    window.lookupEntries = undefined;
    window.entryCount = count;
    audioUrls = {};
    selectedDictionaries = {};
    document.getElementById('entries-container').innerHTML = '';
    reportButtonRects();
    window.renderPopup();
    requestAnimationFrame(() => {
        document.scrollingElement.scrollTop = 0;
        requestAnimationFrame(() => {
            document.scrollingElement.scrollTop = 0;
        });
    });
}

function snapshot() {
    const container = document.getElementById('entries-container');
    return {
        nodes: [...container.childNodes],
        scrollTop: document.scrollingElement.scrollTop,
        lookupEntries: window.lookupEntries,
        entryCount: window.entryCount,
    };
}

function restore(s) {
    const container = document.getElementById('entries-container');
    container.replaceChildren(...s.nodes);
    window.lookupEntries = s.lookupEntries;
    window.entryCount = s.entryCount;
    audioUrls = {};
    selectedDictionaries = {};
    requestAnimationFrame(reportButtonRects);
    requestAnimationFrame(() => {
        document.scrollingElement.scrollTop = s.scrollTop;
    });
}

function navigate(org, to) {
    if (!org.length) {
        return;
    }
    to.push(snapshot());
    restore(org.pop());
}
window.navigateBack = () => navigate(backStack, forwardStack);
window.navigateForward = () => navigate(forwardStack, backStack);

const MASONRY_GAP = 5;
const HAS_NATIVE_MASONRY = CSS.supports('display', 'grid-lanes');
let masonryRaf = null;
let masonryObserver = null;

function layoutMasonry() {
    if (!window.twoColumnLayout || HAS_NATIVE_MASONRY) {
        return;
    }
    document.querySelectorAll('#entries-container .glossary-sections:not(.single-section)').forEach(section => {
        const columnWidth = (section.clientWidth - MASONRY_GAP) / 2;
        const columnHeights = [0, 0];
        [...section.children].forEach(item => {
            const column = columnHeights[0] <= columnHeights[1] ? 0 : 1;
            const x = column * (columnWidth + MASONRY_GAP);
            const y = columnHeights[column];
            item.style.width = `${columnWidth}px`;
            item.style.transform = `translate(${x}px, ${y}px)`;
            item.style.visibility = 'visible';
            columnHeights[column] += item.offsetHeight + MASONRY_GAP;
        });

        section.style.height = `${Math.max(columnHeights[0], columnHeights[1]) - MASONRY_GAP}px`;
    });
}

function scheduleMasonry() {
    if (!window.twoColumnLayout || HAS_NATIVE_MASONRY || masonryRaf) {
        return;
    }
    masonryRaf = requestAnimationFrame(() => {
        masonryRaf = null;
        layoutMasonry();
        reportButtonRects();
    });
}

function observeMasonry(root) {
    if (!window.twoColumnLayout || HAS_NATIVE_MASONRY || root.classList.contains('single-section')) {
        return;
    }
    masonryObserver ??= new ResizeObserver(scheduleMasonry);
    [...root.children].forEach(item => masonryObserver.observe(item));
    scheduleMasonry();
}

window.addEventListener('resize', () => {
    requestAnimationFrame(reportButtonRects);
    scheduleMasonry();
});

document.addEventListener('toggle', () => requestAnimationFrame(reportButtonRects), true);

window.renderPopup = function() {
    const container = document.getElementById('entries-container');
    if (!window.entryCount) {
        return;
    }

    (async () => {
        for (let idx = 0; idx < window.entryCount; idx++) {
            window.lookupEntries ??= [];
            if (!window.lookupEntries[idx]) {
                const entries = await webkit.messageHandlers.getEntries.postMessage({
                    start: idx,
                    count: Math.min(4, window.entryCount - idx)
                });
                entries.forEach((entry, offset) => {
                    window.lookupEntries[idx + offset] = entry;
                });
            }
            const entry = window.lookupEntries[idx];
            if (!entry) {
                continue;
            }

            if (idx > 0) {
                container.appendChild(document.createElement('hr'));
            }

            const entryDiv = el('div', { className: 'entry' });
            entryDiv.appendChild(createEntryHeader(entry, idx));

            if (window.audioEnableAutoplay && window.audioSources?.length && idx === 0) {
                setTimeout(() => {
                    playEntryAudio(idx);
                }, 70);
            }

            const tags = createTags(entry);
            if (tags) {
                entryDiv.appendChild(tags);
            }

            container.appendChild(entryDiv);

            const glossarySections = el('div', { className: 'glossary-sections' });
            entryDiv.appendChild(glossarySections);

            const grouped = {};
            entry.glossaries.forEach(g => {
                (grouped[g.dictionary] ??= []).push({
                    content: g.content,
                    definitionTags: g.definitionTags,
                    termTags: g.termTags
                });
            });

            const dictNames = Object.keys(grouped);
            glossarySections.classList.toggle('single-section', dictNames.length === 1);
            for (let dictIdx = 0; dictIdx < dictNames.length; dictIdx++) {
                glossarySections.appendChild(createGlossarySection(dictNames[dictIdx], grouped[dictNames[dictIdx]], dictIdx === 0, idx));
                if (idx === 0) {
                    scheduleMasonry();
                    await new Promise(r => requestAnimationFrame(r));
                }
            }
            observeMasonry(glossarySections);

            if (idx > 0) {
                await new Promise(r => requestAnimationFrame(r));
            }
        }

        container.querySelectorAll('.glossary-content ruby').forEach(ruby => {
            ruby.childNodes.forEach(node => {
                if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
                    const span = document.createElement('span');
                    span.textContent = node.textContent;
                    node.replaceWith(span);
                }
            });
        });
    })();

    if (window.twoColumnLayout && !document.getElementById('popup-two-column-layout')) {
        const layoutStyle = document.createElement('style');
        layoutStyle.id = 'popup-two-column-layout';
        layoutStyle.textContent = (HAS_NATIVE_MASONRY
                                   ? [
                                       `.glossary-sections { display: grid-lanes; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: ${MASONRY_GAP}px; align-items: start; margin-top: calc(8px * var(--popup-scale)); }`,
                                       `.glossary-sections > .glossary-group { margin-top: 0; }`,
                                       `.glossary-sections.single-section { display: block; }`,
                                   ]
                                   : [
                                       `.glossary-sections { position: relative; margin-top: calc(8px * var(--popup-scale)); }`,
                                       `.glossary-sections > .glossary-group { margin-top: 0; }`,
                                       `.glossary-sections:not(.single-section) > .glossary-group { position: absolute; left: 0; top: 0; visibility: hidden; }`,
                                       `.glossary-sections.single-section { display: block; }`,
                                   ]
                                   ).join('\n');
        document.body.appendChild(layoutStyle);
    }

    if (window.compactGlossaries && !document.getElementById('popup-compact-glossaries')) {
        const glossaryStyle = document.createElement('style');
        glossaryStyle.id = 'popup-compact-glossaries';
        glossaryStyle.textContent = `
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
            ul[data-sc-content="glossary"] > li:not(:last-child)::after,
            ol[data-sc-content="glossary"] > li:not(:last-child)::after,
            .glossary-list > li:not(:last-child)::after {
                content: " | ";
                opacity: 0.6;
            }
        `;
        document.body.appendChild(glossaryStyle);
    }

    if (window.compactPitchAccents && !document.getElementById('popup-compact-pitch-accents')) {
        const pitchStyle = document.createElement('style');
        pitchStyle.id = 'popup-compact-pitch-accents';
        pitchStyle.textContent = `
            .pitch-entries, .pitch-entries > li { display: inline; }
            .pitch-entries > li { white-space: nowrap; }
            .pitch-entries > li:not(:last-child)::after { content: " | "; opacity: 0.6; white-space: normal; }
            .pitch-dict-label { margin-right: 4px; }
        `;
        document.body.appendChild(pitchStyle);
    }

    if (window.customCSS && !document.getElementById('popup-custom-css')) {
        const customStyle = document.createElement('style');
        customStyle.id = 'popup-custom-css';
        customStyle.textContent = window.customCSS;
        document.body.appendChild(customStyle);
    }

    if (container.clickAttached) {
        return;
    }
    container.clickAttached = true;
    container.addEventListener('click', (e) => {
        const target = e.target?.nodeType === Node.TEXT_NODE ? e.target.parentElement : e.target;
        if (target?.closest('summary')) {
            return;
        }
        if (!target?.closest('.glossary-content') && !target?.closest('.expr-tag')) {
            webkit.messageHandlers.tapOutside.postMessage(null);
            return;
        }
        const selected = window.hoshiSelection?.selectText(e.clientX, e.clientY, window.scanLength);
        if (!selected) {
            webkit.messageHandlers.tapOutside.postMessage(null);
            return;
        }
    });
};
