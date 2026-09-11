<script lang="ts">
	import { errorText } from '$lib/api/read';
	let { error, retry }: { error: Error | null; retry: () => void } = $props();
</script>

<div class="feedback" role="alert">
	<h2>暂时无法加载</h2>
	<p>{errorText(error)}</p>
	<button class="button" onclick={retry}>重试</button>
</div>
