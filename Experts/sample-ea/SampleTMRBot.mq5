//+------------------------------------------------------------------+
//|                                                  SampleTMRBot.mq5 |
//|                        Copyright 2024, The Market Robo Inc.       |
//|                                        https://themarketrobo.com  |
//+------------------------------------------------------------------+
//
// SAMPLE EXPERT ADVISOR — SDK INTEGRATION DEMO
// =============================================
// Demonstrates ROBOT (Expert Advisor) integration with TheMarketRobo SDK v1.1+.
//
// What this sample shows:
//   1. Extending CTheMarketRobo_Base with PRODUCT_TYPE_ROBOT
//   2. Implementing a 19-field configuration schema via IRobotConfig
//   3. Handling remote configuration change requests from the dashboard
//   4. Handling remote symbol change requests from the dashboard
//   5. Sending Market Watch symbols at session start
//   6. Generating a unique magic number per session
//
// NOTE: This EA does NOT place any trades.
//       It is designed purely to test SDK connectivity.
//
// USAGE:
//   1. Set your API Key in the InpApiKey input parameter
//   2. Attach the EA to any chart
//   3. Monitor the Experts tab for connection status
//   4. Use the customer dashboard to send config/symbol changes
//   5. Alerts will appear when changes are received
//
// SDK QUICK REFERENCE (Robot):
//   - Extend CTheMarketRobo_Base(uuid, new YourConfig())
//   - Call on_init(api_key, magic_number) from OnInit()
//   - Call on_deinit(reason) from OnDeinit()
//   - Call on_timer() from OnTimer()
//   - Call on_tick() from OnTick()
//   - Call on_chart_event(...) from OnChartEvent()
//   - Override on_config_changed() and on_symbol_changed() for live updates
//
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, The Market Robo Inc."
#property link      "https://themarketrobo.com"
#property version   "1.01"
#property description "Sample EA — TheMarketRobo SDK integration demo (ROBOT product type)"
#property description "Connects to backend, handles remote config and symbol changes"
#property description "No trading performed — connectivity test only"
#property strict

//+------------------------------------------------------------------+
//| SDK Include                                                        |
//+------------------------------------------------------------------+
// Single include — brings in all SDK classes, managers, and the
// unified CTheMarketRobo_Base class that supports both robots and indicators.
#include <themarketrobo/TheMarketRobo_SDK.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
input string InpApiKey = "b7e4a951-24da-4b40-85da-0cd46d88076a";  // API Key (required)

//+------------------------------------------------------------------+
//| Robot Version UUID                                                 |
//+------------------------------------------------------------------+
// Identifies this robot version on TheMarketRobo server.
// Replace with the UUID issued for your robot during submission/registration.
const string ROBOT_VERSION_UUID = "263b48b2-efae-4528-9acf-b4456d7c9e37";

//+------------------------------------------------------------------+
//|                                                                    |
//|   CONFIGURATION CLASS IMPLEMENTATION                               |
//|                                                                    |
//+------------------------------------------------------------------+
/**
 * @class CSampleRobotConfig
 * @brief Implementation of IRobotConfig for the sample EA
 * 
 * This class defines 19 configuration fields matching the
 * complex-robot-config.json schema. It demonstrates:
 *   - Integer, decimal, boolean, radio, and multiple field types
 *   - Field grouping and ordering
 *   - Minimum/maximum constraints
 *   - Field dependencies (dependsOn)
 *   - Options for radio and multiple selection fields
 */
class CSampleRobotConfig : public IRobotConfig
{
private:
    //==========================================================================
    // CONFIGURATION VALUES - Organized by Group
    //==========================================================================
    
    // Strategy Group
    string m_trading_strategy;              // scalping, day_trading, swing_trading, position_trading
    int    m_scalping_timeframe_minutes;    // 1-15 minutes
    
    // Risk Management Group
    int    m_max_trades;                    // Maximum concurrent trades (1-50)
    double m_lot_size;                      // Trade size in lots (0.01-10.0)
    bool   m_use_dynamic_lot_sizing;        // Enable/disable dynamic sizing
    double m_risk_per_trade_percent;        // Risk percentage (0.1-5.0)
    double m_stop_loss_pips;                // Stop loss in pips (5-500)
    double m_take_profit_pips;              // Take profit in pips (5-1000)
    
    // Advanced Features Group
    bool   m_use_trailing_stop;             // Enable trailing stop
    double m_trailing_stop_distance;        // Trailing distance in pips (5-100)
    bool   m_use_breakeven;                 // Move stop to breakeven
    double m_breakeven_trigger_pips;        // Breakeven trigger in pips (5-100)
    
    // Trading Hours Group
    string m_trading_sessions[];            // Active sessions array
    bool   m_avoid_news_events;             // Avoid high-impact news
    int    m_news_buffer_minutes;           // Minutes to avoid before/after news
    
    // Entry Conditions Group
    double m_max_spread_pips;               // Maximum spread to trade (0.5-10)
    int    m_min_candle_body_pips;          // Minimum candle body size (1-100)
    string m_order_execution_mode;          // instant, market, pending
    int    m_max_slippage_pips;             // Maximum slippage (0-20)
    
    // Notifications Group
    bool   m_enable_email_alerts;           // Enable email notifications
    string m_alert_events[];                // Events to alert on

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //+------------------------------------------------------------------+
    CSampleRobotConfig() : IRobotConfig()
    {
        // Define the configuration schema
        define_schema();
        
        // Apply default values to all fields
        apply_defaults();
        
        Print("SampleRobotConfig: Configuration initialized with defaults");
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                        |
    //+------------------------------------------------------------------+
    ~CSampleRobotConfig()
    {
        // Base class handles schema cleanup
    }
    
    //+------------------------------------------------------------------+
    //| Define Schema - Creates the configuration field definitions       |
    //+------------------------------------------------------------------+
    /**
     * Defines all 19 configuration fields with their types, constraints,
     * and metadata. This schema matches complex-robot-config.json
     */
    virtual void define_schema() override
    {
        if(CheckPointer(m_schema) == POINTER_INVALID) return;
        
        //==================================================================
        // STRATEGY GROUP
        //==================================================================
        
        // Trading Strategy (radio selection)
        m_schema.add_field(
            CConfigField::create_radio("trading_strategy", "Trading Strategy", true, "scalping")
                .with_option("scalping", "Scalping")
                .with_option("day_trading", "Day Trading")
                .with_option("swing_trading", "Swing Trading")
                .with_option("position_trading", "Position Trading")
                .with_description("Select the primary trading strategy for this robot")
                .with_group("Strategy", 1)
        );
        
        // Scalping Timeframe (depends on trading_strategy == scalping)
        CConfigDependency* dep_scalping = new CConfigDependency();
        dep_scalping.set_string_value("trading_strategy", CONDITION_EQUALS, "scalping");
        m_schema.add_field(
            CConfigField::create_integer("scalping_timeframe_minutes", "Scalping Timeframe (minutes)", true, 5)
                .with_range(1, 15)
                .with_step(1)
                .with_description("Timeframe in minutes for scalping strategy")
                .with_group("Strategy", 2)
                .with_depends_on(dep_scalping)
        );
        
        //==================================================================
        // RISK MANAGEMENT GROUP
        //==================================================================
        
        // Maximum Concurrent Trades
        m_schema.add_field(
            CConfigField::create_integer("max_trades", "Maximum Concurrent Trades", true, 5)
                .with_range(1, 50)
                .with_step(1)
                .with_description("Maximum number of trades to open simultaneously")
                .with_tooltip("Recommended: 3-10 for beginners, 10-25 for experienced, 25+ for experts")
                .with_group("Risk Management", 1)
        );
        
        // Lot Size
        m_schema.add_field(
            CConfigField::create_decimal("lot_size", "Lot Size", true, 0.01)
                .with_range(0.01, 10.0)
                .with_step(0.01)
                .with_precision(2)
                .with_description("Trade size in lots")
                .with_tooltip("0.01 = micro lot, 0.1 = mini lot, 1.0 = standard lot")
                .with_group("Risk Management", 2)
        );
        
        // Use Dynamic Lot Sizing
        m_schema.add_field(
            CConfigField::create_boolean("use_dynamic_lot_sizing", "Use Dynamic Lot Sizing", true, false)
                .with_description("Automatically adjust lot size based on account balance")
                .with_group("Risk Management", 3)
        );
        
        // Risk Per Trade Percent (depends on use_dynamic_lot_sizing == true)
        CConfigDependency* dep_dynamic = new CConfigDependency();
        dep_dynamic.set_bool_value("use_dynamic_lot_sizing", CONDITION_EQUALS, true);
        m_schema.add_field(
            CConfigField::create_decimal("risk_per_trade_percent", "Risk Per Trade (%)", true, 1.0)
                .with_range(0.1, 5.0)
                .with_step(0.1)
                .with_precision(1)
                .with_description("Percentage of account balance to risk per trade")
                .with_group("Risk Management", 4)
                .with_depends_on(dep_dynamic)
        );
        
        // Stop Loss
        m_schema.add_field(
            CConfigField::create_decimal("stop_loss_pips", "Stop Loss (pips)", true, 20.0)
                .with_range(5.0, 500.0)
                .with_step(5.0)
                .with_precision(1)
                .with_description("Stop loss distance in pips")
                .with_group("Risk Management", 5)
        );
        
        // Take Profit
        m_schema.add_field(
            CConfigField::create_decimal("take_profit_pips", "Take Profit (pips)", true, 40.0)
                .with_range(5.0, 1000.0)
                .with_step(5.0)
                .with_precision(1)
                .with_description("Take profit distance in pips")
                .with_group("Risk Management", 6)
        );
        
        //==================================================================
        // ADVANCED FEATURES GROUP
        //==================================================================
        
        // Use Trailing Stop
        m_schema.add_field(
            CConfigField::create_boolean("use_trailing_stop", "Use Trailing Stop Loss", true, false)
                .with_description("Enable trailing stop loss to lock in profits")
                .with_group("Advanced Features", 1)
        );
        
        // Trailing Stop Distance (depends on use_trailing_stop == true)
        CConfigDependency* dep_trailing = new CConfigDependency();
        dep_trailing.set_bool_value("use_trailing_stop", CONDITION_EQUALS, true);
        m_schema.add_field(
            CConfigField::create_decimal("trailing_stop_distance", "Trailing Stop Distance (pips)", true, 15.0)
                .with_range(5.0, 100.0)
                .with_step(5.0)
                .with_precision(1)
                .with_description("Distance in pips for trailing stop")
                .with_group("Advanced Features", 2)
                .with_depends_on(dep_trailing)
        );
        
        // Use Breakeven
        m_schema.add_field(
            CConfigField::create_boolean("use_breakeven", "Move Stop to Breakeven", true, true)
                .with_description("Automatically move stop loss to breakeven when in profit")
                .with_group("Advanced Features", 3)
        );
        
        // Breakeven Trigger (depends on use_breakeven == true)
        CConfigDependency* dep_breakeven = new CConfigDependency();
        dep_breakeven.set_bool_value("use_breakeven", CONDITION_EQUALS, true);
        m_schema.add_field(
            CConfigField::create_decimal("breakeven_trigger_pips", "Breakeven Trigger (pips)", true, 20.0)
                .with_range(5.0, 100.0)
                .with_step(5.0)
                .with_precision(1)
                .with_description("Profit in pips required to trigger breakeven")
                .with_group("Advanced Features", 4)
                .with_depends_on(dep_breakeven)
        );
        
        //==================================================================
        // TRADING HOURS GROUP
        //==================================================================
        
        // Trading Sessions (multiple selection)
        string default_sessions[];
        ArrayResize(default_sessions, 2);
        default_sessions[0] = "london";
        default_sessions[1] = "newyork";
        m_schema.add_field(
            CConfigField::create_multiple("trading_sessions", "Active Trading Sessions", true)
                .with_option("tokyo", "Tokyo (00:00 - 09:00 UTC)")
                .with_option("london", "London (08:00 - 17:00 UTC)")
                .with_option("newyork", "New York (13:00 - 22:00 UTC)")
                .with_option("sydney", "Sydney (22:00 - 07:00 UTC)")
                .with_selection_limits(1, 4)
                .with_default_selections(default_sessions)
                .with_description("Select which trading sessions to be active during")
                .with_tooltip("London and New York overlap (13:00-17:00 UTC) provides highest liquidity")
                .with_group("Trading Hours", 1)
        );
        
        // Avoid News Events
        m_schema.add_field(
            CConfigField::create_boolean("avoid_news_events", "Avoid High-Impact News Events", true, true)
                .with_description("Pause trading during major economic news releases")
                .with_group("Trading Hours", 2)
        );
        
        // News Buffer Minutes (depends on avoid_news_events == true)
        CConfigDependency* dep_news = new CConfigDependency();
        dep_news.set_bool_value("avoid_news_events", CONDITION_EQUALS, true);
        m_schema.add_field(
            CConfigField::create_integer("news_buffer_minutes", "News Buffer (minutes)", true, 30)
                .with_range(5, 120)
                .with_step(5)
                .with_description("Minutes before and after news to avoid trading")
                .with_group("Trading Hours", 3)
                .with_depends_on(dep_news)
        );
        
        //==================================================================
        // ENTRY CONDITIONS GROUP
        //==================================================================
        
        // Max Spread
        m_schema.add_field(
            CConfigField::create_decimal("max_spread_pips", "Maximum Spread (pips)", true, 2.0)
                .with_range(0.5, 10.0)
                .with_step(0.5)
                .with_precision(1)
                .with_description("Maximum allowed spread to open trades")
                .with_tooltip("Trades won't open if spread exceeds this value")
                .with_group("Entry Conditions", 1)
        );
        
        // Min Candle Body
        m_schema.add_field(
            CConfigField::create_integer("min_candle_body_pips", "Minimum Candle Body (pips)", true, 10)
                .with_range(1, 100)
                .with_step(1)
                .with_description("Minimum candle body size required for signal")
                .with_group("Entry Conditions", 2)
        );
        
        // Order Execution Mode
        m_schema.add_field(
            CConfigField::create_radio("order_execution_mode", "Order Execution Mode", true, "instant")
                .with_option("instant", "Instant Execution")
                .with_option("market", "Market Execution")
                .with_option("pending", "Pending Orders")
                .with_description("How orders should be executed")
                .with_group("Entry Conditions", 3)
        );
        
        // Max Slippage (depends on order_execution_mode == instant)
        CConfigDependency* dep_instant = new CConfigDependency();
        dep_instant.set_string_value("order_execution_mode", CONDITION_EQUALS, "instant");
        m_schema.add_field(
            CConfigField::create_integer("max_slippage_pips", "Maximum Slippage (pips)", true, 3)
                .with_range(0, 20)
                .with_step(1)
                .with_description("Maximum allowed slippage in pips")
                .with_group("Entry Conditions", 4)
                .with_depends_on(dep_instant)
        );
        
        //==================================================================
        // NOTIFICATIONS GROUP
        //==================================================================
        
        // Enable Email Alerts
        m_schema.add_field(
            CConfigField::create_boolean("enable_email_alerts", "Enable Email Alerts", true, false)
                .with_description("Send email notifications for trades and events")
                .with_group("Notifications", 1)
        );
        
        // Alert Events (depends on enable_email_alerts == true)
        string default_alerts[];
        ArrayResize(default_alerts, 2);
        default_alerts[0] = "trade_open";
        default_alerts[1] = "trade_close";
        CConfigDependency* dep_email = new CConfigDependency();
        dep_email.set_bool_value("enable_email_alerts", CONDITION_EQUALS, true);
        m_schema.add_field(
            CConfigField::create_multiple("alert_events", "Alert Events", true)
                .with_option("trade_open", "Trade Opened")
                .with_option("trade_close", "Trade Closed")
                .with_option("stop_loss_hit", "Stop Loss Hit")
                .with_option("take_profit_hit", "Take Profit Hit")
                .with_option("error", "Error Occurred")
                .with_selection_limits(1, 5)
                .with_default_selections(default_alerts)
                .with_description("Select which events trigger email alerts")
                .with_group("Notifications", 2)
                .with_depends_on(dep_email)
        );
        
        Print("SampleRobotConfig: Schema defined with ", m_schema.get_field_count(), " fields");
    }
    
    //+------------------------------------------------------------------+
    //| Apply Defaults - Set all configuration values to defaults         |
    //+------------------------------------------------------------------+
    virtual void apply_defaults() override
    {
        // Strategy
        m_trading_strategy = "scalping";
        m_scalping_timeframe_minutes = 5;
        
        // Risk Management
        m_max_trades = 5;
        m_lot_size = 0.01;
        m_use_dynamic_lot_sizing = false;
        m_risk_per_trade_percent = 1.0;
        m_stop_loss_pips = 20.0;
        m_take_profit_pips = 40.0;
        
        // Advanced Features
        m_use_trailing_stop = false;
        m_trailing_stop_distance = 15.0;
        m_use_breakeven = true;
        m_breakeven_trigger_pips = 20.0;
        
        // Trading Hours
        ArrayResize(m_trading_sessions, 2);
        m_trading_sessions[0] = "london";
        m_trading_sessions[1] = "newyork";
        m_avoid_news_events = true;
        m_news_buffer_minutes = 30;
        
        // Entry Conditions
        m_max_spread_pips = 2.0;
        m_min_candle_body_pips = 10;
        m_order_execution_mode = "instant";
        m_max_slippage_pips = 3;
        
        // Notifications
        m_enable_email_alerts = false;
        ArrayResize(m_alert_events, 2);
        m_alert_events[0] = "trade_open";
        m_alert_events[1] = "trade_close";
    }
    
    //+------------------------------------------------------------------+
    //| To JSON - Serialize current configuration to JSON string          |
    //+------------------------------------------------------------------+
    virtual string to_json() override
    {
        CJAVal config(JA_OBJECT);
        
        // Strategy
        CJAVal* ts = new CJAVal(); ts.set_string(m_trading_strategy); config.Add("trading_strategy", ts);
        CJAVal* stm = new CJAVal(); stm.set_long(m_scalping_timeframe_minutes); config.Add("scalping_timeframe_minutes", stm);
        
        // Risk Management
        CJAVal* mt = new CJAVal(); mt.set_long(m_max_trades); config.Add("max_trades", mt);
        CJAVal* ls = new CJAVal(); ls.set_double(m_lot_size); config.Add("lot_size", ls);
        CJAVal* udls = new CJAVal(); udls.set_bool(m_use_dynamic_lot_sizing); config.Add("use_dynamic_lot_sizing", udls);
        CJAVal* rpt = new CJAVal(); rpt.set_double(m_risk_per_trade_percent); config.Add("risk_per_trade_percent", rpt);
        CJAVal* slp = new CJAVal(); slp.set_double(m_stop_loss_pips); config.Add("stop_loss_pips", slp);
        CJAVal* tpp = new CJAVal(); tpp.set_double(m_take_profit_pips); config.Add("take_profit_pips", tpp);
        
        // Advanced Features
        CJAVal* uts = new CJAVal(); uts.set_bool(m_use_trailing_stop); config.Add("use_trailing_stop", uts);
        CJAVal* tsd = new CJAVal(); tsd.set_double(m_trailing_stop_distance); config.Add("trailing_stop_distance", tsd);
        CJAVal* ub = new CJAVal(); ub.set_bool(m_use_breakeven); config.Add("use_breakeven", ub);
        CJAVal* btp = new CJAVal(); btp.set_double(m_breakeven_trigger_pips); config.Add("breakeven_trigger_pips", btp);
        
        // Trading Hours - sessions array
        CJAVal* tss = new CJAVal(JA_ARRAY);
        for(int i = 0; i < ArraySize(m_trading_sessions); i++)
        {
            CJAVal* s = new CJAVal(); s.set_string(m_trading_sessions[i]); tss.Add(s);
        }
        config.Add("trading_sessions", tss);
        CJAVal* ane = new CJAVal(); ane.set_bool(m_avoid_news_events); config.Add("avoid_news_events", ane);
        CJAVal* nbm = new CJAVal(); nbm.set_long(m_news_buffer_minutes); config.Add("news_buffer_minutes", nbm);
        
        // Entry Conditions
        CJAVal* msp = new CJAVal(); msp.set_double(m_max_spread_pips); config.Add("max_spread_pips", msp);
        CJAVal* mcbp = new CJAVal(); mcbp.set_long(m_min_candle_body_pips); config.Add("min_candle_body_pips", mcbp);
        CJAVal* oem = new CJAVal(); oem.set_string(m_order_execution_mode); config.Add("order_execution_mode", oem);
        CJAVal* mspp = new CJAVal(); mspp.set_long(m_max_slippage_pips); config.Add("max_slippage_pips", mspp);
        
        // Notifications
        CJAVal* eea = new CJAVal(); eea.set_bool(m_enable_email_alerts); config.Add("enable_email_alerts", eea);
        CJAVal* aes = new CJAVal(JA_ARRAY);
        for(int i = 0; i < ArraySize(m_alert_events); i++)
        {
            CJAVal* e = new CJAVal(); e.set_string(m_alert_events[i]); aes.Add(e);
        }
        config.Add("alert_events", aes);
        
        return config.serialize();
    }
    
    //+------------------------------------------------------------------+
    //| Update From JSON - Update configuration from server response      |
    //+------------------------------------------------------------------+
    virtual bool update_from_json(const CJAVal &config_json) override
    {
        // Strategy
        if(config_json.has_key("trading_strategy")) m_trading_strategy = config_json["trading_strategy"].get_string();
        if(config_json.has_key("scalping_timeframe_minutes")) m_scalping_timeframe_minutes = (int)config_json["scalping_timeframe_minutes"].get_long();
        
        // Risk Management
        if(config_json.has_key("max_trades")) m_max_trades = (int)config_json["max_trades"].get_long();
        if(config_json.has_key("lot_size")) m_lot_size = config_json["lot_size"].get_double();
        if(config_json.has_key("use_dynamic_lot_sizing")) m_use_dynamic_lot_sizing = config_json["use_dynamic_lot_sizing"].get_bool();
        if(config_json.has_key("risk_per_trade_percent")) m_risk_per_trade_percent = config_json["risk_per_trade_percent"].get_double();
        if(config_json.has_key("stop_loss_pips")) m_stop_loss_pips = config_json["stop_loss_pips"].get_double();
        if(config_json.has_key("take_profit_pips")) m_take_profit_pips = config_json["take_profit_pips"].get_double();
        
        // Advanced Features
        if(config_json.has_key("use_trailing_stop")) m_use_trailing_stop = config_json["use_trailing_stop"].get_bool();
        if(config_json.has_key("trailing_stop_distance")) m_trailing_stop_distance = config_json["trailing_stop_distance"].get_double();
        if(config_json.has_key("use_breakeven")) m_use_breakeven = config_json["use_breakeven"].get_bool();
        if(config_json.has_key("breakeven_trigger_pips")) m_breakeven_trigger_pips = config_json["breakeven_trigger_pips"].get_double();
        
        // Trading Hours
        if(config_json.has_key("avoid_news_events")) m_avoid_news_events = config_json["avoid_news_events"].get_bool();
        if(config_json.has_key("news_buffer_minutes")) m_news_buffer_minutes = (int)config_json["news_buffer_minutes"].get_long();
        
        // Entry Conditions
        if(config_json.has_key("max_spread_pips")) m_max_spread_pips = config_json["max_spread_pips"].get_double();
        if(config_json.has_key("min_candle_body_pips")) m_min_candle_body_pips = (int)config_json["min_candle_body_pips"].get_long();
        if(config_json.has_key("order_execution_mode")) m_order_execution_mode = config_json["order_execution_mode"].get_string();
        if(config_json.has_key("max_slippage_pips")) m_max_slippage_pips = (int)config_json["max_slippage_pips"].get_long();
        
        // Notifications
        if(config_json.has_key("enable_email_alerts")) m_enable_email_alerts = config_json["enable_email_alerts"].get_bool();
        
        Print("SampleRobotConfig: Configuration updated from JSON");
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Update Field - Update a single field by name                      |
    //+------------------------------------------------------------------+
    virtual bool update_field(string field_name, string new_value) override
    {
        // Strategy
        if(field_name == "trading_strategy") { m_trading_strategy = new_value; return true; }
        if(field_name == "scalping_timeframe_minutes") { m_scalping_timeframe_minutes = (int)StringToInteger(new_value); return true; }
        
        // Risk Management
        if(field_name == "max_trades") { m_max_trades = (int)StringToInteger(new_value); return true; }
        if(field_name == "lot_size") { m_lot_size = StringToDouble(new_value); return true; }
        if(field_name == "use_dynamic_lot_sizing") { m_use_dynamic_lot_sizing = (new_value == "true" || new_value == "1"); return true; }
        if(field_name == "risk_per_trade_percent") { m_risk_per_trade_percent = StringToDouble(new_value); return true; }
        if(field_name == "stop_loss_pips") { m_stop_loss_pips = StringToDouble(new_value); return true; }
        if(field_name == "take_profit_pips") { m_take_profit_pips = StringToDouble(new_value); return true; }
        
        // Advanced Features
        if(field_name == "use_trailing_stop") { m_use_trailing_stop = (new_value == "true" || new_value == "1"); return true; }
        if(field_name == "trailing_stop_distance") { m_trailing_stop_distance = StringToDouble(new_value); return true; }
        if(field_name == "use_breakeven") { m_use_breakeven = (new_value == "true" || new_value == "1"); return true; }
        if(field_name == "breakeven_trigger_pips") { m_breakeven_trigger_pips = StringToDouble(new_value); return true; }
        
        // Trading Hours
        if(field_name == "avoid_news_events") { m_avoid_news_events = (new_value == "true" || new_value == "1"); return true; }
        if(field_name == "news_buffer_minutes") { m_news_buffer_minutes = (int)StringToInteger(new_value); return true; }
        
        // Entry Conditions
        if(field_name == "max_spread_pips") { m_max_spread_pips = StringToDouble(new_value); return true; }
        if(field_name == "min_candle_body_pips") { m_min_candle_body_pips = (int)StringToInteger(new_value); return true; }
        if(field_name == "order_execution_mode") { m_order_execution_mode = new_value; return true; }
        if(field_name == "max_slippage_pips") { m_max_slippage_pips = (int)StringToInteger(new_value); return true; }
        
        // Notifications
        if(field_name == "enable_email_alerts") { m_enable_email_alerts = (new_value == "true" || new_value == "1"); return true; }
        
        Print("SampleRobotConfig: Unknown field: ", field_name);
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Get Field As String - Get a field value as string                 |
    //+------------------------------------------------------------------+
    virtual string get_field_as_string(string field_name) override
    {
        // Strategy
        if(field_name == "trading_strategy") return m_trading_strategy;
        if(field_name == "scalping_timeframe_minutes") return IntegerToString(m_scalping_timeframe_minutes);
        
        // Risk Management
        if(field_name == "max_trades") return IntegerToString(m_max_trades);
        if(field_name == "lot_size") return DoubleToString(m_lot_size, 2);
        if(field_name == "use_dynamic_lot_sizing") return m_use_dynamic_lot_sizing ? "true" : "false";
        if(field_name == "risk_per_trade_percent") return DoubleToString(m_risk_per_trade_percent, 1);
        if(field_name == "stop_loss_pips") return DoubleToString(m_stop_loss_pips, 1);
        if(field_name == "take_profit_pips") return DoubleToString(m_take_profit_pips, 1);
        
        // Advanced Features
        if(field_name == "use_trailing_stop") return m_use_trailing_stop ? "true" : "false";
        if(field_name == "trailing_stop_distance") return DoubleToString(m_trailing_stop_distance, 1);
        if(field_name == "use_breakeven") return m_use_breakeven ? "true" : "false";
        if(field_name == "breakeven_trigger_pips") return DoubleToString(m_breakeven_trigger_pips, 1);
        
        // Trading Hours
        if(field_name == "avoid_news_events") return m_avoid_news_events ? "true" : "false";
        if(field_name == "news_buffer_minutes") return IntegerToString(m_news_buffer_minutes);
        
        // Entry Conditions
        if(field_name == "max_spread_pips") return DoubleToString(m_max_spread_pips, 1);
        if(field_name == "min_candle_body_pips") return IntegerToString(m_min_candle_body_pips);
        if(field_name == "order_execution_mode") return m_order_execution_mode;
        if(field_name == "max_slippage_pips") return IntegerToString(m_max_slippage_pips);
        
        // Notifications
        if(field_name == "enable_email_alerts") return m_enable_email_alerts ? "true" : "false";
        
        return "";
    }
};


//+------------------------------------------------------------------+
//|                                                                    |
//|   SAMPLE ROBOT CLASS IMPLEMENTATION                                |
//|                                                                    |
//+------------------------------------------------------------------+
/**
 * @class CSampleBot
 * @brief Sample Expert Advisor using the unified CTheMarketRobo_Base SDK class.
 *
 * ## SDK Usage (Robot Path)
 * - Extends CTheMarketRobo_Base, passing the UUID and a config object.
 * - Calls on_init(api_key, magic_number) — robot overload (2 arguments).
 * - Overrides on_tick() for per-tick logic (no trading here — demo only).
 * - Overrides on_config_changed() and on_symbol_changed() to react to
 *   live parameter updates pushed from the customer dashboard.
 *
 * ## What Changes vs Old SDK
 * - Class now inherits CTheMarketRobo_Base (was CTheMarketRobo_Bot_Base).
 *   The old name still works as a backwards-compat alias, but new code
 *   should use CTheMarketRobo_Base directly.
 * - on_tick(), on_config_changed(), on_symbol_changed() are now virtual
 *   with default empty implementations — no longer pure virtual.
 *   Overriding them is still required for meaningful robot behaviour.
 * - on_calculate() is available as a virtual stub (only used for indicators).
 */
class CSampleBot : public CTheMarketRobo_Base
{
private:
    int m_tick_count;

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //+------------------------------------------------------------------+
    // Pass UUID + config to the base class.
    // The base class stores the config and validates it in on_init().
    CSampleBot() : CTheMarketRobo_Base(ROBOT_VERSION_UUID, new CSampleRobotConfig())
    {
        m_tick_count = 0;
        Print("==============================================");
        Print("  SAMPLE TMR BOT — TEST ONLY (NO TRADING)  ");
        Print("  Product type: ROBOT (Expert Advisor)      ");
        Print("==============================================");
    }

    //+------------------------------------------------------------------+
    //| Destructor                                                        |
    //+------------------------------------------------------------------+
    ~CSampleBot()
    {
        Print("SampleBot: Destructor called, total ticks processed: ", m_tick_count);
    }

    //+------------------------------------------------------------------+
    //| on_tick — called on every new price tick                          |
    //+------------------------------------------------------------------+
    // This is the robot's main execution hook.
    // In a real EA you would place/manage orders here.
    // In this demo we only count ticks and log every 1000.
    virtual void on_tick() override
    {
        m_tick_count++;

        if(m_tick_count % 1000 == 0)
        {
            Print("SampleBot: Tick #", m_tick_count, " (no trading — demo mode)");
        }
    }

    //+------------------------------------------------------------------+
    //| on_config_changed — server pushed a config change request         |
    //+------------------------------------------------------------------+
    // Called by CTheMarketRobo_Base after the SDK has:
    //   1. Received the change request in the heartbeat response
    //   2. Validated each field against the schema
    //   3. Applied accepted fields to CSampleRobotConfig via update_field()
    //   4. Sent the result back to the server in the next heartbeat
    //
    // At this point your config object already holds the new values.
    // React to the change here (e.g. adjust trading parameters).
    virtual void on_config_changed(string event_json) override
    {
        Alert("CONFIG CHANGE RECEIVED — see Experts tab for details");

        Print("============================================================");
        Print("| CONFIG CHANGE REQUEST RECEIVED                           |");
        Print("============================================================");
        Print("Event: ", event_json);
        Print("All changes accepted in demo mode.");
        Print("============================================================");

        CJAVal event;
        if(event.parse(event_json) && event.has_key("request_id"))
        {
            Print("Request ID: ", event["request_id"].get_string());
        }
    }

    //+------------------------------------------------------------------+
    //| on_symbol_changed — server pushed a symbol active_to_trade change |
    //+------------------------------------------------------------------+
    // Called after the SDK has:
    //   1. Received the symbol change request in the heartbeat response
    //   2. Called SymbolSelect() for each requested symbol
    //   3. Updated the internal symbol list
    //   4. Sent the result back to the server in the next heartbeat
    //
    // React here — e.g. close positions on symbols marked inactive.
    virtual void on_symbol_changed(string event_json) override
    {
        Alert("SYMBOL CHANGE RECEIVED — see Experts tab for details");

        Print("============================================================");
        Print("| SYMBOL CHANGE REQUEST RECEIVED                           |");
        Print("============================================================");
        Print("Event: ", event_json);
        Print("All changes accepted in demo mode.");
        Print("============================================================");

        CJAVal event;
        if(event.parse(event_json) && event.has_key("request_id"))
        {
            Print("Request ID: ", event["request_id"].get_string());
        }
    }
};


//+------------------------------------------------------------------+
//|                                                                    |
//|   GLOBAL VARIABLES                                                 |
//|                                                                    |
//+------------------------------------------------------------------+
CSampleBot *g_robot = NULL;


//+------------------------------------------------------------------+
//|                                                                    |
//|   MQL5 LIFECYCLE EVENT HANDLERS                                    |
//|                                                                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("============================================================");
    Print("| SampleTMRBot Initialization                               |");
    Print("| Product type: ROBOT (Expert Advisor)                     |");
    Print("============================================================");

    if(InpApiKey == "")
    {
        Print("ERROR: API Key is required!");
        Alert("SampleTMRBot: API Key is required — set the InpApiKey input parameter.");
        return INIT_PARAMETERS_INCORRECT;
    }

    // Generate a unique magic number per session so the backend can
    // correlate all orders placed by this EA instance.
    MathSrand((int)TimeLocal());
    long magic_number = MathRand() * MathRand() + (long)GetTickCount();
    Print("SampleTMRBot: Generated magic number = ", magic_number);

    g_robot = new CSampleBot();
    if(CheckPointer(g_robot) == POINTER_INVALID)
    {
        Print("ERROR: Failed to allocate CSampleBot instance!");
        Alert("SampleTMRBot: Memory allocation failed!");
        return INIT_FAILED;
    }

    // Robot overload: on_init(api_key, magic_number)
    // The base class will:
    //   1. Collect static fields (account, terminal, broker)
    //   2. Collect Market Watch symbols as session_symbols
    //   3. POST /robot/start to register the session
    //   4. Parse and store the initial robot_config from the response
    //   5. Start the periodic heartbeat timer
    int result = g_robot.on_init(InpApiKey, magic_number);
    if(result != INIT_SUCCEEDED)
    {
        Print("ERROR: SDK initialization failed (code=", result, ")");
        return result;
    }

    Print("============================================================");
    Print("| SampleTMRBot Ready — Connected to TheMarketRobo Backend  |");
    Print("| Demo mode: no trades will be placed                      |");
    Print("| Waiting for config/symbol change requests...             |");
    Print("============================================================");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("SampleTMRBot: OnDeinit reason=", reason);

    if(CheckPointer(g_robot) != POINTER_INVALID)
    {
        g_robot.on_deinit(reason);
        delete g_robot;
        g_robot = NULL;
    }

    Print("SampleTMRBot: Shutdown complete.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    if(CheckPointer(g_robot) != POINTER_INVALID)
        g_robot.on_tick();
}

//+------------------------------------------------------------------+
//| Timer function — drives SDK heartbeats                             |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(CheckPointer(g_robot) != POINTER_INVALID)
        g_robot.on_timer();
}

//+------------------------------------------------------------------+
//| Chart event handler — routes SDK custom events                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(CheckPointer(g_robot) != POINTER_INVALID)
        g_robot.on_chart_event(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
