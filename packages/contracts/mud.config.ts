import { defineWorld } from "@latticexyz/world";

export default defineWorld({
  tables: {
    EntryPoint: {
      schema: {
        addr: "address",
      },
      key: [],
    },
  },
});
