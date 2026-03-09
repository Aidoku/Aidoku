//
//  selection.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

window.hoshiSelection = {
    selection: null,
    scanDelimiters: '。、！？…‥「」『』（）()【】〈〉《》〔〕｛｝{}［］[]・：；:;，,.─\n\r',
    sentenceDelimiters: '。！？.!?\n\r',
    isVertical() {
        return window.getComputedStyle(document.body).writingMode === "vertical-rl";
    },
    
    isScanBoundary(char) {
        return /^[\s\u3000]$/.test(char) || this.scanDelimiters.includes(char);
    },
    
    isFurigana(node) {
        const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
        return !!el?.closest('rt, rp');
    },
    
    findParagraph(node) {
        let el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
        return el?.closest('p, .glossary-content') || null;
    },
    
    createWalker(rootNode) {
        const root = rootNode || document.body;
        
        return document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: (n) => this.isFurigana(n) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
        });
    },
    
    getCaretRange(x, y) {
        if (document.caretPositionFromPoint) {
            const pos = document.caretPositionFromPoint(x, y);
            if (!pos) {
                return null;
            }
            
            const range = document.createRange();
            range.setStart(pos.offsetNode, pos.offset);
            range.collapse(true);
            return range;
        } else {
            const element = document.elementFromPoint(x, y);
            if (!element) {
                return null;
            }
            
            const container = element.closest('p, div, span, ruby, a') || document.body;
            const walker = this.createWalker(container);
            
            const range = document.createRange();
            let node;
            while (node = walker.nextNode()) {
                for (let i = 0; i < node.textContent.length; i++) {
                    range.setStart(node, i);
                    range.setEnd(node, i + 1);
                    const rect = range.getBoundingClientRect();
                    if (rect.left <= x && x <= rect.right && rect.top <= y && y <= rect.bottom) {
                        range.collapse(true);
                        return range;
                    }
                }
            }
            return document.caretRangeFromPoint(x, y);
        }
    },
    
    getCharacterAtPoint(x, y) {
        const range = this.getCaretRange(x, y);
        if (!range) {
            return null;
        }
        
        const node = range.startContainer;
        if (node.nodeType !== Node.TEXT_NODE) {
            return null;
        }
        
        if (this.isFurigana(node)) {
            return null;
        }
        
        const text = node.textContent;
        const caret = range.startOffset;
        
        for (const offset of [caret, caret - 1, caret + 1]) {
            if (offset < 0 || offset >= text.length) {
                continue;
            }
            
            const charRange = document.createRange();
            charRange.setStart(node, offset);
            charRange.setEnd(node, offset + 1);
            const rect = charRange.getBoundingClientRect();
            
            const inside = x >= rect.left && x <= rect.right
            && y >= rect.top && y <= rect.bottom;
            
            if (inside) {
                if (this.isScanBoundary(text[offset])) {
                    return null;
                }
                return { node, offset };
            }
        }
        
        return null;
    },
    
    getSentence(startNode, startOffset) {
        const container = this.findParagraph(startNode) || document.body;
        const walker = this.createWalker(container);
        
        walker.currentNode = startNode;
        const partsBefore = [];
        let node = startNode;
        let limit = startOffset;
        
        while (node) {
            const text = node.textContent;
            let foundStart = false;
            for (let i = limit - 1; i >= 0; i--) {
                if (this.sentenceDelimiters.includes(text[i])) {
                    partsBefore.push(text.slice(i + 1, limit));
                    foundStart = true;
                    break;
                }
            }
            
            if (foundStart) {
                break;
            }
            
            partsBefore.push(text.slice(0, limit));
            node = walker.previousNode();
            if (node) limit = node.textContent.length;
        }
        
        walker.currentNode = startNode;
        const partsAfter = [];
        node = startNode;
        let start = startOffset;
        
        while (node) {
            const text = node.textContent;
            let foundEnd = false;
            
            for (let i = start; i < text.length; i++) {
                if (this.sentenceDelimiters.includes(text[i])) {
                    partsAfter.push(text.slice(start, i + 1));
                    foundEnd = true;
                    break;
                }
            }
            
            if (foundEnd) {
                break;
            }
            
            partsAfter.push(text.slice(start));
            
            node = walker.nextNode();
            start = 0;
        }
        
        return (partsBefore.reverse().join('') + partsAfter.join('')).trim();
    },
    
    selectText(x, y, maxLength) {
        const hit = this.getCharacterAtPoint(x, y);
        
        if (!hit) {
            this.clearHighlight();
            return null;
        }
        
        // Dismiss popup if tapping on the first character of the current selection
        if (this.selection &&
            hit.node === this.selection.startNode &&
            hit.offset === this.selection.startOffset) {
            this.clearHighlight();
            return null;
        }
        
        this.clearHighlight();
        
        const container = this.findParagraph(hit.node) || document.body;
        const walker = this.createWalker(container);
        
        let text = '';
        let node = hit.node;
        let offset = hit.offset;
        let ranges = [];
        
        walker.currentNode = node;
        while (text.length < maxLength && node) {
            const content = node.textContent;
            const start = offset;
            
            while (offset < content.length && text.length < maxLength) {
                const char = content[offset];
                if (this.isScanBoundary(char)) {
                    break;
                }
                text += char;
                offset++;
            }
            
            if (offset > start) {
                ranges.push({ node, start, end: offset });
            }
            
            if (offset < content.length || text.length >= maxLength) {
                break;
            }
            
            node = walker.nextNode();
            offset = 0;
        }
        
        if (!text) {
            return null;
        }
        
        this.selection = {
            startNode: hit.node,
            startOffset: hit.offset,
            ranges,
            text
        };
        
        const sentence = this.getSentence(hit.node, hit.offset);
        webkit.messageHandlers.textSelected.postMessage({
            text,
            sentence,
            rect: this.getSelectionRect()
        });
        
        return text;
    },
    
    getSelectionRect() {
        if (!this.selection?.ranges.length) {
            return null;
        }
        
        const first = this.selection.ranges[0];
        const range = document.createRange();
        range.setStart(first.node, first.start);
        range.setEnd(first.node, first.start + 1);
        
        const rect = range.getBoundingClientRect();
        return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    },
    
    highlightSelection(charCount) {
        if (!this.selection?.ranges.length) {
            return;
        }
        
        const highlights = [];
        let remaining = charCount;
        
        for (const r of this.selection.ranges) {
            if (remaining <= 0) {
                break;
            }
            
            const length = r.end - r.start;
            const end = remaining >= length ? r.end : r.start + remaining;
            
            const range = document.createRange();
            range.setStart(r.node, r.start);
            range.setEnd(r.node, end);
            highlights.push(range);
            
            remaining -= length;
        }
        
        CSS.highlights?.set('hoshi-selection', new Highlight(...highlights));
    },
    
    clearHighlight() {
        window.getSelection()?.removeAllRanges();
        CSS.highlights?.clear();
        this.selection = null;
    }
};
