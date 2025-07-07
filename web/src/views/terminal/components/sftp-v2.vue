<template>
  <div class="sftp_v2_tab_container">
    test
  </div>
</template>

<script setup>

</script>

<style lang="scss" scoped>
.sftp_v2_tab_container {
  height: 100%;
  section {
    height: 100%;
    display: flex;
    .box {
      $header_height: 30px;
      .header {
        user-select: none;
        height: $header_height;
        padding: 0 5px;
        background-color: var(--el-fill-color-light);
        display: flex;
        align-items: center;
        font-size: 12px;
        .operation {
          display: flex;
          align-items: center;
          // margin-right: 20px;
          .img {
            margin: 0 5px;
            width: 20px;
            height: 20px;
            img {
              width: 100%;
              height: 100%;
            }
            &:hover {
              background: #cec4c4;
            }
          }
        }
        .filter_input {
          width: 200px;
          min-width: 200px;
          margin: 0 20px 0 10px;
        }
        .path_input {
          width: 450px;
          min-width: 450px;
        }
        .path {
          flex: 1;
          user-select: all;
          cursor: pointer;
          &:hover {
            color: var(--el-color-primary);
          }
        }
        .up-file-progress-wrap {
          min-width: 200px;
          max-width: 350px;
        }
      }
    }
  }
}
</style>
