<script lang="ts">
	import { resolve } from '$app/paths';
</script>

<svelte:head><title>演示说明 · AI Fitness</title></svelte:head>
<header class="page-heading">
	<div>
		<div class="eyebrow">PRODUCT PREVIEW</div>
		<h1>先体验一次训练复盘</h1>
		<p class="subtle">从列表到曲线，用同一份数据连接桌面和手机。</p>
	</div>
</header>
<section class="surface">
	<h2>这个 demo 可以做什么</h2>
	<p>
		浏览骑行与跑步、按运动筛选、打开训练详情、选择指标样本，并查看合成轨迹。页面顶部的场景选择器可以体验慢速、空数据和失败状态。
	</p>
	<h2>数据与功能范围</h2>
	<p>
		全部训练与轨迹为合成演示数据，不会读取或保存你的健康记录。轨迹展示为无底图示意，也不会请求第三方地图。
	</p>
	<p>
		API 类型来自 main 分支的新契约。后端业务接口和认证尚未实现，因此当前没有真实登录、FIT
		上传或记录编辑。图中的统计值为演示响应提供的汇总；前端不计算训练负荷或健康评分。
	</p>
	<a class="button primary" href={resolve('/workouts')}>开始查看训练</a>
</section>

<style>
	section {
		max-width: 760px;
	}
	p {
		color: #606672;
		margin: 14px 0 28px;
		line-height: 1.8;
	}
	h2 {
		font-size: 20px;
	}
</style>
