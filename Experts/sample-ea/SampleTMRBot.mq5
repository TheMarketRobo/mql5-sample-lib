//+------------------------------------------------------------------+
//|                                                  SampleTMRBot.mq5 |
//|                        Copyright 2024, The Market Robo Inc.       |
//|                                        https://themarketrobo.com  |
//+------------------------------------------------------------------+
//
// SAMPLE EXPERT ADVISOR - SDK INTEGRATION DEMO
// ============================================
// This EA demonstrates how to:
//   1. Integrate with TheMarketRobo SDK
//   2. Implement a configuration schema with 19 fields
//   3. Handle configuration change requests from the server
//   4. Handle symbol change requests from the server
//   5. Use watchlist symbols for session initialization
//
// NOTE: This EA does NOT perform any trading operations.
//       It is designed purely to test SDK connectivity.
//
// USAGE:
//   1. Set your API Key in the input parameter
//   2. Attach the EA to any chart
//   3. Monitor the Experts tab for connection status
//   4. Use the customer dashboard to send config/symbol changes
//   5. Alerts will appear when changes are received
//
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, The Market Robo Inc."
#property link      "https://themarketrobo.com"
#property version   "1.00"
#property description "Sample EA demonstrating TheMarketRobo SDK integration"
#property description "This EA connects to the backend and handles config/symbol changes"
#property description "No trading is performed - for testing purposes only"
#property strict

//+------------------------------------------------------------------+
//| SDK Include                                                        |
//+------------------------------------------------------------------+
// Include the main SDK header file which provides all necessary
// classes and utilities for TheMarketRobo integration
#include <themarketrobo/TheMarketRobo_SDK.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
// API Key is required for authentication with TheMarketRobo backend
input string InpApiKey = "";  // API Key (required)

//+------------------------------------------------------------------+
//| Robot Version UUID                                                 |
//+------------------------------------------------------------------+
// This UUID identifies the robot version on the server
// Replace with your actual UUID for production use
const string ROBOT_VERSION_UUID = "thisisatestuuidplaceholder";

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
 * @brief Sample EA implementation using TheMarketRobo SDK
 * 
 * This class demonstrates how to:
 *   - Extend CTheMarketRobo_Bot_Base
 *   - Handle on_tick() events (empty - no trading)
 *   - Handle on_config_changed() events with Alert
 *   - Handle on_symbol_changed() events with Alert
 */
class CSampleBot : public CTheMarketRobo_Bot_Base
{
private:
    int m_tick_count;  // Count ticks for logging
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //+------------------------------------------------------------------+
    CSampleBot() : CTheMarketRobo_Bot_Base(ROBOT_VERSION_UUID, new CSampleRobotConfig())
    {
        m_tick_count = 0;
        Print("==============================================");
        Print("  SAMPLE TMR BOT - TEST ONLY (NO TRADING)");
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
    //| On Tick - Called on every price tick                              |
    //+------------------------------------------------------------------+
    /**
     * This method is called on every price tick.
     * In this sample EA, we do NOT perform any trading operations.
     * We only log tick activity periodically for monitoring.
     */
    virtual void on_tick() override
    {
        m_tick_count++;
        
        // Log every 1000 ticks to show EA is running
        if(m_tick_count % 1000 == 0)
        {
            Print("SampleBot: Tick count = ", m_tick_count, " (no trading - test mode)");
        }
    }
    
    //+------------------------------------------------------------------+
    //| On Config Changed - Handle configuration change requests          |
    //+------------------------------------------------------------------+
    /**
     * This method is called when the server sends a configuration change request.
     * The SDK has already processed the change and updated the configuration.
     * 
     * In this sample EA:
     *   - We show an Alert to notify the user
     *   - We log the change details to the Experts tab
     *   - We ALWAYS accept all changes (no rejection logic)
     * 
     * @param event_json JSON string containing change details
     */
    virtual void on_config_changed(string event_json) override
    {
        //==================================================================
        // ALERT USER ABOUT CONFIG CHANGE
        //==================================================================
        Alert("=========================================");
        Alert("  CONFIGURATION CHANGE REQUEST RECEIVED!");
        Alert("=========================================");
        Alert("Details: ", event_json);
        
        //==================================================================
        // LOG CHANGE DETAILS
        //==================================================================
        Print("============================================================");
        Print("| CONFIG CHANGE REQUEST                                     |");
        Print("============================================================");
        Print("Event JSON: ", event_json);
        Print("Action: Change ACCEPTED (all changes accepted in test mode)");
        Print("============================================================");
        
        // Parse the event to show individual field changes
        CJAVal event;
        if(event.parse(event_json))
        {
            if(event.has_key("changes"))
            {
                Print("Changed fields:");
                // The changes would be logged by the SDK
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| On Symbol Changed - Handle symbol change requests                 |
    //+------------------------------------------------------------------+
    /**
     * This method is called when the server sends a symbol change request.
     * The SDK has already processed the change and updated the symbols.
     * 
     * In this sample EA:
     *   - We show an Alert to notify the user
     *   - We log the change details to the Experts tab
     *   - We ALWAYS accept all changes (no rejection logic)
     * 
     * @param event_json JSON string containing change details
     */
    virtual void on_symbol_changed(string event_json) override
    {
        //==================================================================
        // ALERT USER ABOUT SYMBOL CHANGE
        //==================================================================
        Alert("=========================================");
        Alert("  SYMBOL CHANGE REQUEST RECEIVED!");
        Alert("=========================================");
        Alert("Details: ", event_json);
        
        //==================================================================
        // LOG CHANGE DETAILS
        //==================================================================
        Print("============================================================");
        Print("| SYMBOL CHANGE REQUEST                                     |");
        Print("============================================================");
        Print("Event JSON: ", event_json);
        Print("Action: Change ACCEPTED (all changes accepted in test mode)");
        Print("============================================================");
        
        // Parse the event to show individual symbol changes
        CJAVal event;
        if(event.parse(event_json))
        {
            if(event.has_key("symbols"))
            {
                Print("Symbol changes:");
                // The symbols would be logged by the SDK
            }
        }
    }
};


//+------------------------------------------------------------------+
//|                                                                    |
//|   GLOBAL VARIABLES                                                 |
//|                                                                    |
//+------------------------------------------------------------------+
CSampleBot* g_robot = NULL;  // Global robot instance


//+------------------------------------------------------------------+
//|                                                                    |
//|   MQL5 EVENT HANDLERS                                              |
//|                                                                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("============================================================");
    Print("| SampleTMRBot Initialization                               |");
    Print("============================================================");
    
    //==================================================================
    // VALIDATE API KEY
    //==================================================================
    if(InpApiKey == "")
    {
        Print("ERROR: API Key is required!");
        Alert("SampleTMRBot: API Key is required! Please set the API Key input parameter.");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    //==================================================================
    // GENERATE RANDOM MAGIC NUMBER
    //==================================================================
    // Use combination of random numbers and tick count for uniqueness
    MathSrand((int)TimeLocal());
    long magic_number = MathRand() * MathRand() + (long)GetTickCount();
    Print("Generated Magic Number: ", magic_number);
    
    //==================================================================
    // CREATE ROBOT INSTANCE
    //==================================================================
    g_robot = new CSampleBot();
    
    if(CheckPointer(g_robot) == POINTER_INVALID)
    {
        Print("ERROR: Failed to create robot instance!");
        Alert("SampleTMRBot: Failed to create robot instance!");
        return INIT_FAILED;
    }
    
    //==================================================================
    // INITIALIZE SDK CONNECTION
    //==================================================================
    // The on_init() method will:
    //   1. Collect static data (account, terminal, broker info)
    //   2. Collect watchlist symbols for session_symbols
    //   3. Connect to TheMarketRobo backend
    //   4. Start the session
    //   5. Set up the heartbeat timer
    
    int result = g_robot.on_init(InpApiKey, magic_number);
    
    if(result != INIT_SUCCEEDED)
    {
        Print("ERROR: Robot initialization failed!");
        // Robot will clean up and remove itself
        return result;
    }
    
    Print("============================================================");
    Print("| SampleTMRBot Ready - Connected to TheMarketRobo Backend   |");
    Print("| Mode: TEST ONLY (No trading)                              |");
    Print("| Waiting for config/symbol change requests...              |");
    Print("============================================================");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("============================================================");
    Print("| SampleTMRBot Shutdown                                     |");
    Print("| Reason: ", reason);
    Print("============================================================");
    
    if(CheckPointer(g_robot) != POINTER_INVALID)
    {
        // Gracefully terminate SDK session
        g_robot.on_deinit(reason);
        
        // Clean up memory
        delete g_robot;
        g_robot = NULL;
    }
    
    Print("SampleTMRBot: Shutdown complete");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    if(CheckPointer(g_robot) != POINTER_INVALID)
    {
        g_robot.on_tick();
    }
}

//+------------------------------------------------------------------+
//| Timer function - SDK heartbeat                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(CheckPointer(g_robot) != POINTER_INVALID)
    {
        g_robot.on_timer();
    }
}

//+------------------------------------------------------------------+
//| ChartEvent function - SDK event handling                           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(CheckPointer(g_robot) != POINTER_INVALID)
    {
        g_robot.on_chart_event(id, lparam, dparam, sparam);
    }
}

//+------------------------------------------------------------------+
