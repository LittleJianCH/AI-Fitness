<script lang="ts">
	import { m } from '$lib/paraglide/messages.js';
	import { errorText, ApiError } from '$lib/api/request';

	let { error, retry }: { error: Error | null; retry: () => void } = $props();
</script>

<div class="feedback" role="alert">
	<h2>{m.error_heading()}</h2>
	<p>{errorText(error)}</p>
	{#if error instanceof ApiError && error.requestId && /^[A-Za-z0-9_-]{1,128}$/.test(error.requestId)}<p
			class="small"
		>
			{m.error_request_id({ id: error.requestId })}
		</p>{/if}
	<button class="button" onclick={retry}>{m.action_retry()}</button>
</div>
