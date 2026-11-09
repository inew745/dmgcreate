/* DMG Creator — download site
   Scroll behaviour: a progress bar, reveals, a little parallax, a scroll-driven
   drag demo, step highlighting and a typed terminal. All of it is skipped when
   the visitor asks for reduced motion. */

(function () {
    'use strict';

    var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var clamp = function (v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; };

    var progress = document.getElementById('progress');
    var nav = document.getElementById('nav');
    var demo = document.getElementById('demo');
    var dragIcon = document.getElementById('dragIcon');
    var captions = Array.prototype.slice.call(
        document.querySelectorAll('#demoCaptions li'));
    var steps = Array.prototype.slice.call(document.querySelectorAll('.step'));
    var parallax = Array.prototype.slice.call(
        document.querySelectorAll('[data-parallax]'));

    /* ── reveal on scroll ─────────────────────────────────────────── */
    var revealables = Array.prototype.slice.call(document.querySelectorAll('.reveal'));

    if (reduced || !('IntersectionObserver' in window)) {
        revealables.forEach(function (el) { el.classList.add('in'); });
    } else {
        // Children of a grid or list come in one after another.
        ['.grid', '.steps'].forEach(function (selector) {
            var group = document.querySelector(selector);
            if (!group) { return; }
            Array.prototype.slice.call(group.children).forEach(function (child, i) {
                child.style.transitionDelay = (i * 70) + 'ms';
            });
        });

        var observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
                if (entry.isIntersecting) {
                    entry.target.classList.add('in');
                    observer.unobserve(entry.target);
                }
            });
        }, { threshold: 0.14, rootMargin: '0px 0px -8% 0px' });

        revealables.forEach(function (el) { observer.observe(el); });
    }

    /* ── scroll-linked work, batched into one frame ───────────────── */
    var ticking = false;
    var lastCaption = -1;
    var lastStep = -1;

    function onScroll() {
        var y = window.pageYOffset || document.documentElement.scrollTop;
        var height = document.documentElement.scrollHeight - window.innerHeight;

        if (progress) {
            progress.style.transform = 'scaleX(' + clamp(height > 0 ? y / height : 0, 0, 1) + ')';
        }
        if (nav) {
            nav.classList.toggle('stuck', y > 8);
        }

        if (!reduced) {
            parallax.forEach(function (el) {
                var rate = parseFloat(el.getAttribute('data-parallax')) || 0;
                var mid = el.getBoundingClientRect().top + el.offsetHeight / 2;
                var offset = (mid - window.innerHeight / 2) * rate;
                el.style.transform = 'translate3d(0,' + offset.toFixed(1) + 'px,0)';
            });
        }

        /* the drag demo: 0 at the top of the pinned section, 1 at the bottom */
        if (demo && dragIcon && !reduced) {
            var rect = demo.getBoundingClientRect();
            var travel = demo.offsetHeight - window.innerHeight;
            var p = travel > 0 ? clamp(-rect.top / travel, 0, 1) : 0;
            // Ease the middle so the icon lingers at both slots.
            var eased = p < 0.5
                ? 2 * p * p
                : 1 - Math.pow(-2 * p + 2, 2) / 2;
            dragIcon.style.setProperty('--p', eased.toFixed(4));

            var index = p < 0.3 ? 0 : (p < 0.68 ? 1 : 2);
            if (index !== lastCaption) {
                captions.forEach(function (li, i) { li.classList.toggle('on', i === index); });
                lastCaption = index;
            }
        }

        /* steps: whichever sits closest to the middle of the screen */
        if (steps.length) {
            var centre = window.innerHeight * 0.5;
            var best = -1;
            var bestDistance = Infinity;
            steps.forEach(function (step, i) {
                var box = step.getBoundingClientRect();
                if (box.bottom < 0 || box.top > window.innerHeight) { return; }
                var distance = Math.abs(box.top + box.height / 2 - centre);
                if (distance < bestDistance) { bestDistance = distance; best = i; }
            });
            if (best !== lastStep) {
                steps.forEach(function (step, i) { step.classList.toggle('active', i === best); });
                lastStep = best;
            }
        }

        ticking = false;
    }

    function requestTick() {
        if (!ticking) {
            ticking = true;
            window.requestAnimationFrame(onScroll);
        }
    }

    window.addEventListener('scroll', requestTick, { passive: true });
    window.addEventListener('resize', requestTick);
    if (captions.length) { captions[0].classList.add('on'); }
    onScroll();

    /* ── the terminal types itself out once it is on screen ───────── */
    var COMMAND = [
        ['./scripts/make-dmg.sh', 'tok-cmd'], [' \\\n    ', ''],
        ['--volname', 'tok-flag'], [' ', ''], ['"My App"', 'tok-str'], [' \\\n    ', ''],
        ['--output', 'tok-flag'], [' ~/Desktop/MyApp.dmg \\\n    ', ''],
        ['--background', 'tok-flag'], [' assets/default-background.png \\\n    ', ''],
        ['--window-size', 'tok-flag'], [' 660,400 \\\n    ', ''],
        ['--icon-size', 'tok-flag'], [' 104 \\\n    ', ''],
        ['--add', 'tok-flag'], [' ', ''], ['"build/My App.app"', 'tok-str'], [' \\\n    ', ''],
        ['--pos', 'tok-flag'], [' ', ''], ['"My App.app:181,186"', 'tok-str'], [' \\\n    ', ''],
        ['--applications-link', 'tok-flag'], [' \\\n    ', ''],
        ['--pos', 'tok-flag'], [' ', ''], ['"Applications:471,186"', 'tok-str'], ['\n\n', ''],
        ['==> Done: ~/Desktop/MyApp.dmg (4.1M)', 'tok-str']
    ];

    var typed = document.getElementById('typed');
    var caret = document.getElementById('caret');
    var box = document.getElementById('terminal-box');

    function renderWhole() {
        typed.innerHTML = '';
        COMMAND.forEach(function (part) {
            var span = document.createElement('span');
            if (part[1]) { span.className = part[1]; }
            span.textContent = part[0];
            typed.appendChild(span);
        });
    }

    function typeOut() {
        var token = 0;
        var char = 0;
        var span = null;

        (function step() {
            if (token >= COMMAND.length) {
                if (caret) { caret.style.display = 'none'; }
                return;
            }
            if (char === 0) {
                span = document.createElement('span');
                if (COMMAND[token][1]) { span.className = COMMAND[token][1]; }
                typed.appendChild(span);
            }
            var text = COMMAND[token][0];
            // Whitespace runs appear in one go; letters arrive one at a time.
            var chunk = /\s/.test(text.charAt(char)) ? text.length - char : 1;
            span.textContent += text.substr(char, chunk);
            char += chunk;
            if (char >= text.length) { token += 1; char = 0; }
            window.setTimeout(step, 13);
        }());
    }

    if (typed) {
        if (reduced || !('IntersectionObserver' in window)) {
            renderWhole();
            if (caret) { caret.style.display = 'none'; }
        } else {
            var typeObserver = new IntersectionObserver(function (entries) {
                entries.forEach(function (entry) {
                    if (entry.isIntersecting) {
                        typeObserver.disconnect();
                        typeOut();
                    }
                });
            }, { threshold: 0.35 });
            typeObserver.observe(box || typed);
        }
    }
}());
