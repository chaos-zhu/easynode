<template>
  <div class="ai_button" @click="handleClick">
    <img src="@/assets/image/coding32.png"  alt="AIHelper" />
    AI Helper
  </div>
</template>

<script setup>
const emit = defineEmits(['click']);
const handleClick = () => {
  emit('click');
};
</script>

<style scoped>
.ai_button {
  cursor: pointer;
  min-width: 100px;
  height: 32px;
  line-height: 32px;
  text-align: center;
  color: #fff;
  font-size: 14px;
  background: #887dfd;
  border-radius: 10px;
  transition: all 0.5s;
  display: flex;
  align-items: center;
  justify-content: center;

  img {
    width: 16px;
    height: 16px;
    margin-right: 4px;
    border-radius: 10%;
  }
}


.ai_button:hover {
  filter: brightness(1.2);
}
</style>