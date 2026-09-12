<script lang="ts">
	let {
		tags = $bindable(),
		pending = $bindable(''),
		disabled = false
	}: { tags: string[]; pending?: string; disabled?: boolean } = $props();
	export function flush() {
		const value = pending.trim();
		if (value && !tags.includes(value)) tags = [...tags, value];
		pending = '';
	}
</script>

<div class="tag-editor">
	<label
		>添加标签<input
			bind:value={pending}
			{disabled}
			placeholder="例如：通勤、轻松跑"
			onkeydown={(event) => {
				if (event.key === 'Enter' && !event.isComposing && event.keyCode !== 229) {
					event.preventDefault();
					flush();
				}
			}}
		/></label
	>
	<button type="button" class="button" {disabled} onclick={flush}>添加标签</button>
</div>
{#if tags.length}<ul class="editable-tags" aria-label="已选标签">
		{#each tags as tag, index (index)}<li>
				<span>{tag}</span><button
					type="button"
					{disabled}
					aria-label={`移除标签 ${tag}`}
					onclick={() => (tags = tags.filter((_, i) => i !== index))}>×</button
				>
			</li>{/each}
	</ul>{/if}

<style>
	.tag-editor {
		display: flex;
		align-items: end;
		gap: 12px;
	}
	.tag-editor label {
		flex: 1;
	}
	.editable-tags {
		list-style: none;
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		padding: 0;
		margin: 0;
	}
	li {
		display: flex;
		align-items: center;
		background: #edf2fa;
		border-radius: 8px;
		padding-left: 12px;
		max-width: 100%;
	}
	li span {
		overflow-wrap: anywhere;
		white-space: pre-wrap;
		min-width: 0;
	}
	li button {
		border: 0;
		background: transparent;
		min-height: 44px;
		min-width: 44px;
		font-size: 22px;
		flex-shrink: 0;
	}
	@media (max-width: 400px) {
		.tag-editor {
			align-items: stretch;
			flex-direction: column;
		}
	}
</style>
