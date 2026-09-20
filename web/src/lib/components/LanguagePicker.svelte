<script lang="ts">
	import { onMount } from 'svelte';
	import { base } from '$app/paths';
	import { m } from '$lib/paraglide/messages.js';
	import { languageCookie, languageOverride, type LanguagePreference } from '$lib/i18n/locale';
	import { languageChangeEvent, languageCommitEvent } from '$lib/i18n/guard.svelte';
	let preference = $state<LanguagePreference>('system');
	let ready = $state(false);
	onMount(() => {
		preference = languageOverride(document.cookie) ?? 'system';
		ready = true;
	});
	function change(event: Event & { currentTarget: HTMLSelectElement }) {
		const next = event.currentTarget.value;
		if (next !== 'en' && next !== 'zh-Hans' && next !== 'system') return;
		if (!window.dispatchEvent(new Event(languageChangeEvent, { cancelable: true }))) {
			event.currentTarget.value = preference;
			return;
		}
		window.dispatchEvent(new Event(languageCommitEvent));
		const secure = location.protocol === 'https:' ? '; Secure' : '';
		document.cookie = `${languageCookie}=${next === 'system' ? '' : next}; Path=${base || '/'}; SameSite=Lax; Max-Age=${next === 'system' ? 0 : 31536000}${secure}`;
		location.reload();
	}
</script>

<select
	aria-label={m.language_label()}
	value={preference}
	onchange={change}
	disabled={!ready}
	data-testid="language-picker"
>
	<option value="system">{m.language_system()}</option><option value="en">English</option><option
		value="zh-Hans">简体中文</option
	>
</select>
