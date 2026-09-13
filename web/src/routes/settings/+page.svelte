<script lang="ts">
	import AccountSettings from '$lib/auth/components/AccountSettings.svelte';

	const demo = import.meta.env.MODE === 'demo';
</script>

<svelte:head><title>账号设置 · AI Fitness</title></svelte:head>
<header class="page-heading">
	<div>
		<div class="eyebrow">YOUR ACCOUNT</div>
		<h1>账号设置</h1>
		<p class="subtle">管理登录设备与账号密码。</p>
	</div>
</header>
{#if demo}<div class="status">
		账号设置需要登录真实账号，演示模式仅供查看。
	</div>{:else}<AccountSettings />{/if}
