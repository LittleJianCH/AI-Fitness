import { onMount } from 'svelte';
import { beforeNavigate } from '$app/navigation';
export const languageChangeEvent = 'fitness-language-change';
export const languageCommitEvent = 'fitness-language-commit';

/** One discard policy for navigation and language reloads, before cookie mutation. */
export function protectUnsavedChanges(
	dirty: () => boolean,
	message: () => string,
	busy = () => false
) {
	let approvedReload = false;
	beforeNavigate((navigation) => {
		if (!approvedReload && dirty() && (navigation.type === 'leave' || !window.confirm(message())))
			navigation.cancel();
	});
	onMount(() => {
		const beforeLanguageChange = (event: Event) => {
			if (busy() || (dirty() && !window.confirm(message()))) event.preventDefault();
		};
		const committed = () => {
			approvedReload = true;
		};
		window.addEventListener(languageChangeEvent, beforeLanguageChange);
		window.addEventListener(languageCommitEvent, committed);
		return () => {
			window.removeEventListener(languageChangeEvent, beforeLanguageChange);
			window.removeEventListener(languageCommitEvent, committed);
		};
	});
}
