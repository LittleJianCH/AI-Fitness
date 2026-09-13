<script lang="ts">
	import { onMount, type Snippet } from 'svelte';

	let { title, onclose, children }: { title: string; onclose: () => void; children: Snippet } =
		$props();
	let dialog: HTMLDialogElement;
	let ready = $state(false);
	onMount(() => {
		const previous = document.activeElement;
		const overflow = document.body.style.overflow;
		dialog.showModal();
		ready = true;
		document.body.style.overflow = 'hidden';
		return () => {
			document.body.style.overflow = overflow;
			if (previous instanceof HTMLElement && previous.isConnected)
				previous.focus({ preventScroll: true });
		};
	});
</script>

<dialog bind:this={dialog} aria-label={title} {onclose}>
	<header>
		<h2>{title}</h2>
		<button class="button" onclick={() => dialog.close()} aria-label="关闭详情">关闭 ×</button>
	</header>
	<div class="dialog-content">
		{#if ready}{@render children()}{/if}
	</div>
</dialog>

<style>
	dialog {
		width: min(1100px, calc(100% - 32px));
		max-height: calc(100dvh - 32px);
		padding: 0;
		border: 1px solid var(--line);
		border-radius: 12px;
		background: var(--panel);
		color: var(--text);
		box-shadow: 0 24px 100px #0005;
	}
	dialog::backdrop {
		background: #050d1b99;
		backdrop-filter: blur(4px);
	}
	header {
		position: sticky;
		top: 0;
		z-index: 2;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		padding: 16px 24px;
		background: var(--panel);
		border-bottom: 1px solid var(--line);
	}
	.dialog-content {
		padding: 24px;
		min-width: 0;
	}
	@media (max-width: 700px) {
		.dialog-content {
			padding: 12px;
		}
		header {
			padding: 12px;
		}
	}
</style>
