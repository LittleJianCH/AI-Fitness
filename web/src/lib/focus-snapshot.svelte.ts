import { tick } from 'svelte';
import type { Snapshot } from '@sveltejs/kit';

export type FocusSnapshot = { key: string | null; scrollY: number };

// History snapshots contain only a control identifier and scroll metadata.
// Query content can mount after SvelteKit's first scroll restoration attempt.
export function createFocusSnapshot() {
	let target = $state<FocusSnapshot | null>(null);
	const snapshot: Snapshot<FocusSnapshot> = {
		capture: () => ({
			key: document.activeElement?.getAttribute('data-return-focus') ?? null,
			scrollY: window.scrollY
		}),
		restore: (saved) => {
			target = saved;
		}
	};
	function restoreFocus(node: HTMLElement) {
		$effect(() => {
			const saved = target;
			if (!saved?.key || node.dataset.returnFocus !== saved.key) return;
			target = null;
			void tick().then(() => {
				if (
					!node.isConnected ||
					(document.activeElement !== document.body && document.activeElement !== node)
				)
					return;
				node.focus({ preventScroll: true });
				window.scrollTo({ top: saved.scrollY, behavior: 'instant' });
			});
		});
	}
	return { snapshot, restoreFocus };
}
