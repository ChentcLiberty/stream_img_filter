package img_filter_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef bit [39:0]  img_filter_pixel_t;
  typedef bit [159:0] img_filter_word_t;

  class img_filter_frame_item extends uvm_sequence_item;
    `uvm_object_utils(img_filter_frame_item)

    int unsigned case_id;
    int unsigned width;
    int unsigned height;
    int unsigned blk_v;
    int unsigned salt;
    int unsigned profile;
    int unsigned half;
    int unsigned row_words;
    int unsigned total_words;
    bit [199:0]  coef_packed;

    byte unsigned coef_valid[$];
    byte unsigned coef_full[$];
    img_filter_word_t input_words[$];
    img_filter_word_t expected_words[$];

    function new(string name = "img_filter_frame_item");
      super.new(name);
    endfunction

    static function automatic int mirror_row(int raw_row, int img_height);
      int tmp;
      tmp = raw_row;

      repeat (2) begin
        if (tmp < 0) begin
          tmp = -tmp - 1;
        end else if (tmp >= img_height) begin
          tmp = (img_height << 1) - 1 - tmp;
        end
      end

      return tmp;
    endfunction

    static function automatic img_filter_pixel_t pack_pixel(
        int b,
        int g,
        int r,
        int a
    );
      img_filter_pixel_t pixel;
      pixel[9:0]   = b[9:0];
      pixel[19:10] = g[9:0];
      pixel[29:20] = r[9:0];
      pixel[39:30] = a[9:0];
      return pixel;
    endfunction

    static function automatic img_filter_pixel_t make_pixel(
        int row_i,
        int col_i,
        int salt_i
    );
      int base;
      base = (row_i * 41 + col_i * 17 + salt_i) & 10'h3ff;
      return pack_pixel(base + 0, base + 1, base + 2, base + 3);
    endfunction

    static function automatic int pixel_channel(img_filter_pixel_t pixel, int channel_idx);
      return pixel[(channel_idx * 10) +: 10];
    endfunction

    static function automatic bit [9:0] norm_chan(int accum_int);
      int norm_int;
      norm_int = accum_int >>> 7;

      if (norm_int < 0) begin
        return 10'd0;
      end
      if (norm_int > 1023) begin
        return 10'h3ff;
      end
      return norm_int[9:0];
    endfunction

    function void set_coeff_profile(int profile_id);
      coef_valid.delete();
      repeat (25) coef_valid.push_back(8'd0);

      case (profile_id)
        1: begin
          coef_valid[0] = 8'd128;
        end
        2: begin
          coef_valid[0] = 8'd32;
          coef_valid[1] = 8'd64;
        end
        3: begin
          coef_valid[0] = 8'd8;
          coef_valid[1] = 8'd24;
          coef_valid[2] = 8'd64;
        end
        4: begin
          coef_valid[0] = 8'd4;
          coef_valid[1] = 8'd12;
          coef_valid[2] = 8'd20;
          coef_valid[3] = 8'd56;
        end
        5: begin
          coef_valid[0] = 8'd2;
          coef_valid[1] = 8'd4;
          coef_valid[2] = 8'd8;
          coef_valid[3] = 8'd16;
          coef_valid[4] = 8'd68;
        end
        6: begin
          coef_valid[0] = 8'd1;
          coef_valid[1] = 8'd1;
          coef_valid[2] = 8'd2;
          coef_valid[3] = 8'd4;
          coef_valid[4] = 8'd8;
          coef_valid[5] = 8'd12;
          coef_valid[6] = 8'd16;
          coef_valid[7] = 8'd40;
        end
        7: begin
          for (int i = 0; i < 24; i++) begin
            coef_valid[i] = 8'd2;
          end
          coef_valid[24] = 8'd32;
        end
        8: begin
          coef_valid[0] = 8'd16;
          coef_valid[1] = 8'd96;
        end
        default: begin
          `uvm_fatal(get_type_name(), $sformatf("unsupported profile_id=%0d", profile_id))
        end
      endcase
    endfunction

    function void expand_coeffs();
      int coef_delta;
      int coef_idx;

      coef_full.delete();
      for (int tap_i = 0; tap_i < int'(blk_v); tap_i++) begin
        coef_delta = (tap_i > int'(half)) ? (tap_i - int'(half)) : (int'(half) - tap_i);
        coef_idx = int'(half) - coef_delta;
        coef_full.push_back(coef_valid[coef_idx]);
      end

      if (coef_full.sum() != 128) begin
        `uvm_fatal(get_type_name(),
            $sformatf("expanded coefficient sum=%0d, expected 128", coef_full.sum()))
      end
    endfunction

    function void build_vectors();
      img_filter_pixel_t src_pixels[][];
      img_filter_pixel_t src_pixel;
      img_filter_word_t packed_word;
      int acc_b;
      int acc_g;
      int acc_r;
      int acc_a;
      int src_row_i;

      if ((blk_v < 1) || (blk_v > 49) || ((blk_v & 1) == 0)) begin
        `uvm_fatal(get_type_name(), $sformatf("invalid blk_v=%0d", blk_v))
      end

      if ((width < 24) || (height < 24)) begin
        `uvm_warning(get_type_name(),
            $sformatf("building out-of-spec small case width=%0d height=%0d", width, height))
      end

      half = (blk_v - 1) / 2;
      row_words = (width + 3) / 4;
      total_words = row_words * height;

      set_coeff_profile(profile);
      expand_coeffs();

      coef_packed = '0;
      for (int i = 0; i < 25; i++) begin
        coef_packed[(i*8) +: 8] = coef_valid[i];
      end

      src_pixels = new[height];
      for (int row_i = 0; row_i < int'(height); row_i++) begin
        src_pixels[row_i] = new[width];
        for (int col_i = 0; col_i < int'(width); col_i++) begin
          src_pixels[row_i][col_i] = make_pixel(row_i, col_i, salt);
        end
      end

      input_words.delete();
      expected_words.delete();

      for (int row_i = 0; row_i < int'(height); row_i++) begin
        for (int word_i = 0; word_i < int'(row_words); word_i++) begin
          packed_word = '0;
          for (int lane_i = 0; lane_i < 4; lane_i++) begin
            int col_i;
            col_i = word_i * 4 + lane_i;
            if (col_i < int'(width)) begin
              packed_word[(lane_i*40) +: 40] = src_pixels[row_i][col_i];
            end
          end
          input_words.push_back(packed_word);
        end
      end

      for (int row_i = 0; row_i < int'(height); row_i++) begin
        for (int word_i = 0; word_i < int'(row_words); word_i++) begin
          packed_word = '0;
          for (int lane_i = 0; lane_i < 4; lane_i++) begin
            int col_i;
            col_i = word_i * 4 + lane_i;
            if (col_i < int'(width)) begin
              acc_b = 0;
              acc_g = 0;
              acc_r = 0;
              acc_a = 0;

              for (int tap_i = 0; tap_i < int'(blk_v); tap_i++) begin
                src_row_i = mirror_row(row_i + tap_i - int'(half), height);
                src_pixel = src_pixels[src_row_i][col_i];
                acc_b += pixel_channel(src_pixel, 0) * coef_full[tap_i];
                acc_g += pixel_channel(src_pixel, 1) * coef_full[tap_i];
                acc_r += pixel_channel(src_pixel, 2) * coef_full[tap_i];
                acc_a += pixel_channel(src_pixel, 3) * coef_full[tap_i];
              end

              packed_word[(lane_i*40) +: 40] = {
                norm_chan(acc_a),
                norm_chan(acc_r),
                norm_chan(acc_g),
                norm_chan(acc_b)
              };
            end
          end
          expected_words.push_back(packed_word);
        end
      end
    endfunction

    function void build_case_by_id(int unsigned requested_case_id);
      case_id = requested_case_id;

      case (requested_case_id)
        1: begin width = 24; height = 24; blk_v = 1;  salt = 0;   profile = 1; end
        2: begin width = 25; height = 24; blk_v = 3;  salt = 17;  profile = 2; end
        3: begin width = 32; height = 25; blk_v = 5;  salt = 53;  profile = 3; end
        4: begin width = 37; height = 24; blk_v = 7;  salt = 91;  profile = 4; end
        5: begin width = 24; height = 31; blk_v = 9;  salt = 123; profile = 5; end
        6: begin width = 33; height = 29; blk_v = 15; salt = 211; profile = 6; end
        7: begin width = 24; height = 24; blk_v = 49; salt = 301; profile = 7; end
        8: begin width = 40; height = 27; blk_v = 3;  salt = 401; profile = 8; end
        9: begin width = 24; height = 64; blk_v = 49; salt = 557; profile = 7; end
        default: begin
          `uvm_fatal(get_type_name(),
              $sformatf("unsupported deterministic case_id=%0d", requested_case_id))
        end
      endcase

      build_vectors();
    endfunction

    function img_filter_frame_item clone_item(string name = "img_filter_frame_item_clone");
      img_filter_frame_item clone_h;
      clone_h = new(name);

      clone_h.case_id = case_id;
      clone_h.width = width;
      clone_h.height = height;
      clone_h.blk_v = blk_v;
      clone_h.salt = salt;
      clone_h.profile = profile;
      clone_h.half = half;
      clone_h.row_words = row_words;
      clone_h.total_words = total_words;
      clone_h.coef_packed = coef_packed;

      foreach (coef_valid[i]) begin
        clone_h.coef_valid.push_back(coef_valid[i]);
      end
      foreach (coef_full[i]) begin
        clone_h.coef_full.push_back(coef_full[i]);
      end
      foreach (input_words[i]) begin
        clone_h.input_words.push_back(input_words[i]);
      end
      foreach (expected_words[i]) begin
        clone_h.expected_words.push_back(expected_words[i]);
      end

      return clone_h;
    endfunction

    function string summary();
      return $sformatf("case=%0d width=%0d height=%0d blk_v=%0d total_words=%0d",
          case_id, width, height, blk_v, total_words);
    endfunction

  endclass

  class img_filter_out_item extends uvm_sequence_item;
    `uvm_object_utils(img_filter_out_item)

    int unsigned     word_idx;
    img_filter_word_t data;

    function new(string name = "img_filter_out_item");
      super.new(name);
    endfunction
  endclass

  class img_filter_base_seq extends uvm_sequence #(img_filter_frame_item);
    `uvm_object_utils(img_filter_base_seq)

    int unsigned case_id = 1;

    function new(string name = "img_filter_base_seq");
      super.new(name);
    endfunction

    task body();
      img_filter_frame_item req_h;

      req_h = img_filter_frame_item::type_id::create("req_h");
      req_h.build_case_by_id(case_id);
      `uvm_info(get_type_name(),
          $sformatf("Starting sequence for %s", req_h.summary()), UVM_MEDIUM)

      start_item(req_h);
      finish_item(req_h);
    endtask
  endclass

  class img_filter_driver extends uvm_driver #(img_filter_frame_item);
    `uvm_component_utils(img_filter_driver)

    virtual img_filter_if vif;
    uvm_analysis_port #(img_filter_frame_item) frame_ap;

    function new(string name = "img_filter_driver", uvm_component parent = null);
      super.new(name, parent);
      frame_ap = new("frame_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual img_filter_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_type_name(), "virtual interface img_filter_if not found")
      end
    endfunction

    task reset_signals();
      vif.in_pix_rdy  <= 1'b0;
      vif.in_pix_data <= '0;
      vif.out_pix_need <= 1'b1;
      vif.frm_start   <= 1'b0;
      vif.img_width   <= '0;
      vif.img_height  <= '0;
      vif.blk_v       <= '0;
      vif.coef        <= '0;
    endtask

    task drive_frame(img_filter_frame_item tr);
      int unsigned in_idx;

      @(negedge vif.clk);
      vif.img_width   <= tr.width - 1;
      vif.img_height  <= tr.height - 1;
      vif.blk_v       <= tr.blk_v[5:0];
      vif.coef        <= tr.coef_packed;
      vif.frm_start   <= 1'b1;
      vif.out_pix_need <= 1'b1;

      @(posedge vif.clk);
      @(negedge vif.clk);
      vif.frm_start <= 1'b0;

      in_idx = 0;
      while (in_idx < tr.total_words) begin
        @(negedge vif.clk);
        if (vif.in_pix_need) begin
          vif.in_pix_rdy  <= 1'b1;
          vif.in_pix_data <= tr.input_words[in_idx];
        end else begin
          vif.in_pix_rdy  <= 1'b0;
          vif.in_pix_data <= '0;
        end

        @(posedge vif.clk);
        if (vif.rst_n && vif.in_pix_rdy && vif.in_pix_need) begin
          in_idx++;
        end
      end

      @(negedge vif.clk);
      vif.in_pix_rdy  <= 1'b0;
      vif.in_pix_data <= '0;
    endtask

    task run_phase(uvm_phase phase);
      reset_signals();

      forever begin
        seq_item_port.get_next_item(req);
        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);
        frame_ap.write(req.clone_item("frame_clone"));
        drive_frame(req);
        seq_item_port.item_done();
      end
    endtask
  endclass

  class img_filter_monitor extends uvm_component;
    `uvm_component_utils(img_filter_monitor)

    virtual img_filter_if vif;
    uvm_analysis_port #(img_filter_out_item) out_ap;
    int unsigned out_word_idx;

    function new(string name = "img_filter_monitor", uvm_component parent = null);
      super.new(name, parent);
      out_ap = new("out_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual img_filter_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_type_name(), "virtual interface img_filter_if not found")
      end
    endfunction

    task run_phase(uvm_phase phase);
      img_filter_out_item item_h;

      out_word_idx = 0;
      forever begin
        @(posedge vif.clk);
        if (!vif.rst_n) begin
          out_word_idx = 0;
        end else begin
          if (vif.frm_start) begin
            out_word_idx = 0;
          end

          if (vif.out_pix_rdy && vif.out_pix_need) begin
            item_h = img_filter_out_item::type_id::create("item_h");
            item_h.word_idx = out_word_idx;
            item_h.data = vif.out_pix_data;
            out_ap.write(item_h);
            out_word_idx++;
          end
        end
      end
    endtask
  endclass

  class img_filter_sequencer extends uvm_sequencer #(img_filter_frame_item);
    `uvm_component_utils(img_filter_sequencer)

    function new(string name = "img_filter_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class img_filter_agent extends uvm_component;
    `uvm_component_utils(img_filter_agent)

    img_filter_driver    drv;
    img_filter_monitor   mon;
    img_filter_sequencer seqr;

    function new(string name = "img_filter_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv  = img_filter_driver::type_id::create("drv", this);
      mon  = img_filter_monitor::type_id::create("mon", this);
      seqr = img_filter_sequencer::type_id::create("seqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  class img_filter_scoreboard extends uvm_component;
    `uvm_component_utils(img_filter_scoreboard)

    uvm_tlm_analysis_fifo #(img_filter_frame_item) frame_fifo;
    uvm_tlm_analysis_fifo #(img_filter_out_item)   out_fifo;

    int unsigned frames_checked;
    int unsigned words_checked;

    function new(string name = "img_filter_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      frame_fifo = new("frame_fifo", this);
      out_fifo   = new("out_fifo", this);
      frames_checked = 0;
      words_checked = 0;
    endfunction

    task run_phase(uvm_phase phase);
      img_filter_frame_item frame_h;
      img_filter_out_item   out_h;

      forever begin
        frame_fifo.get(frame_h);
        `uvm_info(get_type_name(),
            $sformatf("Checking %s", frame_h.summary()), UVM_LOW)

        for (int i = 0; i < frame_h.total_words; i++) begin
          out_fifo.get(out_h);
          if (out_h.word_idx != i) begin
            `uvm_error(get_type_name(),
                $sformatf("word index mismatch expect=%0d actual=%0d", i, out_h.word_idx))
          end

          if (out_h.data !== frame_h.expected_words[i]) begin
            `uvm_fatal(get_type_name(),
                $sformatf({"data mismatch at word %0d for case %0d\n",
                           "expect=%040h\nactual=%040h"},
                    i, frame_h.case_id, frame_h.expected_words[i], out_h.data))
          end
          words_checked++;
        end

        frames_checked++;
        `uvm_info(get_type_name(),
            $sformatf("Frame %0d passed with %0d words", frame_h.case_id, frame_h.total_words),
            UVM_LOW)
      end
    endtask
  endclass

  class img_filter_env extends uvm_component;
    `uvm_component_utils(img_filter_env)

    img_filter_agent      agent;
    img_filter_scoreboard scb;

    function new(string name = "img_filter_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = img_filter_agent::type_id::create("agent", this);
      scb   = img_filter_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.drv.frame_ap.connect(scb.frame_fifo.analysis_export);
      agent.mon.out_ap.connect(scb.out_fifo.analysis_export);
    endfunction
  endclass

  class img_filter_uvm_test extends uvm_test;
    `uvm_component_utils(img_filter_uvm_test)

    img_filter_env env;
    int unsigned case_id;

    function new(string name = "img_filter_uvm_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = img_filter_env::type_id::create("env", this);

      if (!$value$plusargs("CASE_ID=%d", case_id)) begin
        case_id = 1;
      end
    endfunction

    task run_phase(uvm_phase phase);
      img_filter_base_seq seq_h;

      phase.raise_objection(this);
      seq_h = img_filter_base_seq::type_id::create("seq_h");
      seq_h.case_id = case_id;
      seq_h.start(env.agent.seqr);
      wait (env.scb.frames_checked == 1);
      `uvm_info(get_type_name(),
          $sformatf("UVM test completed for deterministic case_id=%0d", case_id), UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

endpackage
